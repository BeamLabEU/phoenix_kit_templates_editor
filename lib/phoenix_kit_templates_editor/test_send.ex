defmodule PhoenixKitTemplatesEditor.TestSend do
  @moduledoc """
  "Send to me" (spec §4.11 П3): one email, to the address of the user
  asking and nobody else, with sample variables, in its layout — as the
  editor shows it. Works where the templates are read only too: it writes
  nothing.

    * The user must see the tab (`PhoenixKitTemplatesEditor.authorize(scope, :read)`).
    * Not more often than once in 30 s per user (`PhoenixKitTemplatesEditor.Throttle`).
    * Sent by the host's `test_send` callback when it has one —
      `test_send(name, locale, user)`, returning `:ok`, `{:ok, _}` or
      `{:error, reason}` (the host's own way of sending, its test mode
      included) — else through `PhoenixKit.Mailer.send_from_template/4`:
      an email core or a module sends with its catalogue entry's built-in
      text, samples and layout; the host's own from the root's files with
      its `sample_variables` and its layout (`layout.txt`, else
      `layout_group`).
    * Every attempt is logged: who, which email, which language, and how
      it went.
  """

  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  require Logger

  alias PhoenixKit.Mailer
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKit.Users.Auth.Scope
  alias PhoenixKit.Utils.RecipientLocale
  alias PhoenixKitTemplatesEditor.Config
  alias PhoenixKitTemplatesEditor.Layouts
  alias PhoenixKitTemplatesEditor.Preview
  alias PhoenixKitTemplatesEditor.Throttle

  @interval_ms 30_000

  @doc """
  Sends email `name` in `locale` to the user of `scope`; `entry` is its
  catalogue entry (`nil` — one of the host's). `{:ok, address}` or
  `{:error, message}` in the page's language. Options: `:interval` (ms).
  """
  @spec deliver(Config.t(), Scope.t() | nil, String.t(), String.t(), map() | nil, keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def deliver(%Config{} = config, scope, name, locale, entry, opts \\ []) do
    with {:ok, user} <- user(scope),
         :ok <- allowed(scope),
         :ok <- throttle(user, opts[:interval] || @interval_ms) do
      result = send_now(config, name, locale, user, entry)
      log(user, name, locale, result)

      case result do
        :ok -> {:ok, user.email}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp user(scope) do
    case Scope.user(scope) do
      %{email: email} = user when is_binary(email) -> {:ok, user}
      _none -> {:error, gettext("the page does not tell who you are.")}
    end
  end

  defp allowed(scope) do
    case PhoenixKitTemplatesEditor.authorize(scope, :read) do
      :ok -> :ok
      {:error, _reason} -> {:error, gettext("you may not see these templates.")}
    end
  end

  defp throttle(user, interval) do
    case Throttle.hit({:test_send, user.uuid || user.email}, interval) do
      :ok ->
        :ok

      {:error, {:wait, seconds}} ->
        {:error,
         gettext("one test email in %{interval} s: wait %{seconds} s.",
           interval: div(interval, 1000),
           seconds: seconds
         )}

      {:error, :unavailable} ->
        {:error,
         gettext("test emails are not available: the module's processes are not running.")}
    end
  end

  defp send_now(config, name, locale, user, entry) do
    case config.test_send do
      nil ->
        name
        |> Mailer.send_from_template(
          user.email,
          variables(config, entry, locale),
          mail_opts(config, name, locale, user, entry)
        )
        |> result()

      callback ->
        callback |> call([name, locale, user]) |> result()
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  catch
    kind, reason -> {:error, Exception.format_banner(kind, reason)}
  end

  defp call({module, function}, args), do: apply(module, function, args)
  defp call(fun, args), do: apply(fun, args)

  defp result(:ok), do: :ok
  defp result({:ok, _whatever}), do: :ok
  defp result({:error, reason}) when is_binary(reason), do: {:error, reason}
  defp result({:error, reason}), do: {:error, inspect(reason)}
  defp result(other), do: {:error, inspect(other)}

  # An email core or a module sends: its samples, in the language.
  defp variables(_config, %{variables: variables}, locale) do
    RecipientLocale.in_locale(locale, fn ->
      case variables do
        fun when is_function(fun, 0) -> fun.()
        map when is_map(map) -> map
        _none -> %{}
      end
    end)
  end

  defp variables(config, _entry, _locale), do: Preview.sample_variables(config)

  defp mail_opts(_config, _name, locale, user, %{} = entry) do
    [
      locale: locale,
      defaults: Map.get(entry, :defaults) || %{},
      layout: Map.get(entry, :layout, true),
      user_uuid: user.uuid
    ]
  end

  defp mail_opts(%Config{root: root} = config, name, locale, user, nil) do
    files = Enum.find_value(Overrides.list(root), [], &(&1.name == name && &1.files))
    group = Layouts.email_layout(root, files) || config.layout_group

    [locale: locale, paths: [root], layout: group || true, user_uuid: user.uuid]
  end

  defp log(user, name, locale, result) do
    outcome =
      case result do
        :ok -> "sent"
        {:error, reason} -> "failed: #{reason}"
      end

    Logger.info(
      "[PhoenixKitTemplatesEditor] test email #{inspect(name)} (#{locale}) to user #{user.uuid}: #{outcome}"
    )
  end
end
