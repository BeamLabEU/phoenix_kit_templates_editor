defmodule PhoenixKitTemplatesEditor.Preview do
  @moduledoc """
  The editor's preview when the host gives none (`preview: nil`): an email
  as core would build it from the files of the root, with the sample
  variables — `{subject, html, text}` for `PhoenixKitTemplatesEditor.Web.Editor`.

  ## An email (a name without a leading `_`)

    * The parts come from `PhoenixKit.Templates.render/4` on the root alone,
      by the language's chain (`ru-RU` → `ru` → no language): the subject
      on one line without a byte-order mark, a blank file counting as none.
      Templates of core's Emails module in the database are not looked at.
    * HTML: the `html` part, else the `markdown` part rendered
      (`PhoenixKit.Email.Markdown`), else the `text` part as paragraphs
      (`PhoenixKit.Email.Layout.text_to_html/1`).
    * Text: the `text` part, else the `markdown` part as text, else the
      `html` part as text (`PhoenixKitTemplatesEditor.HtmlText`).
    * Variables: the sample variables, with the branding
      (`PhoenixKit.Email.Branding`) as core binds it in every part.
    * Unless the HTML is a whole document, it is wrapped in the layout
      (`PhoenixKit.Email.Layout.wrap/3`) of the email's group — its
      `layout.txt`, else `layout_group` — from the root, in the language.

  ## A header, footer or layout (`_header-<g>`, `_footer-<g>`, `_layout-<g>`)

  The first email (`PhoenixKitTemplatesEditor.Catalog.emails/2`, whatever
  `catalog` says) that uses the layout of the part's own name — else the
  first email at all, else a Lorem ipsum — in that layout. A shared
  `_header`/`_footer`/`_layout` is shown the same way in no group (the
  shared chrome); any other name with a `_`, in `layout_group`.

  ## What it refuses

  Before anything is read, the email's template directory and each chrome
  one go through `PhoenixKitTemplatesEditor.Files.check_template/2` — the
  library's lookup follows links and caches what it read, so a link must
  not reach it — and every file the preview then reads, through
  `PhoenixKitTemplatesEditor.Files.check/2`: a link, a file leading out of
  the root or one over `PhoenixKit.Templates.Overrides.max_bytes/0` is an
  `{:error, message}` naming it relative to the root. The work runs in a
  task with a deadline (`:timeout`, 5 s by default).
  """

  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  require Logger

  alias PhoenixKit.Email.Branding
  alias PhoenixKit.Email.Layout
  alias PhoenixKit.Email.Markdown
  alias PhoenixKit.Templates
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Bounded
  alias PhoenixKitTemplatesEditor.Catalog
  alias PhoenixKitTemplatesEditor.Config
  alias PhoenixKitTemplatesEditor.Files
  alias PhoenixKitTemplatesEditor.HtmlText
  alias PhoenixKitTemplatesEditor.Names

  @lorem_subject "Lorem ipsum"
  @lorem_text "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor " <>
                "incididunt ut labore et dolore magna aliqua.\n\nUt enim ad minim veniam, quis " <>
                "nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."

  @type result :: {String.t() | nil, String.t() | nil, String.t() | nil} | {:error, String.t()}

  @doc """
  The preview of template `name` in `locale` (`nil` — the files without a
  language). Options: `:timeout` (ms).
  """
  @spec preview(Config.t(), String.t(), String.t() | nil, keyword()) :: result()
  def preview(%Config{} = config, name, locale, opts \\ []) when is_binary(name) do
    variables = sample_variables(config)

    case Bounded.run(fn -> build(config, name, locale, variables) end, opts[:timeout] || 5_000) do
      {:ok, result} -> result
      {:error, :timeout} -> {:error, gettext("it took too long")}
    end
  end

  @doc """
  The host's sample variables as a map with string keys: the `sample_variables`
  map, or what its callback returns. A callback that fails, or returns
  anything but a map, is logged and gives `%{}`.
  """
  @spec sample_variables(Config.t()) :: %{String.t() => term()}
  def sample_variables(%Config{sample_variables: variables}) do
    case evaluate(variables) do
      map when is_map(map) -> Map.new(map, fn {key, value} -> {to_string(key), value} end)
      other -> log_samples(other)
    end
  rescue
    exception -> log_samples(Exception.message(exception))
  catch
    kind, reason -> log_samples(Exception.format_banner(kind, reason))
  end

  defp evaluate({module, function}), do: apply(module, function, [])
  defp evaluate(fun) when is_function(fun, 0), do: fun.()
  defp evaluate(map), do: map

  defp log_samples(what) do
    Logger.error(
      "[PhoenixKitTemplatesEditor] sample_variables gave no map: #{inspect(what, printable_limit: 200)}"
    )

    %{}
  end

  ## Building

  defp build(config, "_" <> _ = name, locale, variables) do
    group =
      case Names.chrome(name) do
        {_kind, group} -> group
        nil -> config.layout_group
      end

    emails = Catalog.emails(config, locale || config.base_locale)

    case Enum.find(emails, &(&1.layout == group)) || List.first(emails) do
      %{name: first} ->
        with {:ok, email} <- email(config, first, locale, variables) do
          finish(config, email, group, locale)
        end

      nil ->
        finish(config, lorem(), group, locale)
    end
  end

  defp build(config, name, locale, variables) do
    with {:ok, email} <- email(config, name, locale, variables) do
      finish(config, email, email.group, locale)
    end
  end

  defp email(%Config{root: root} = config, name, locale, variables) do
    opts = [locale: locale, paths: [root]]

    with :ok <- check_template(root, name),
         :ok <- check_sources(root, Templates.sources(name, %{}, opts)) do
      variables = Branding.merge(variables, Branding.variables())
      parts = Templates.render(name, %{}, variables, opts)

      [subject, html, text, markdown] =
        Enum.map([:subject, :html, :text, :markdown], &present(parts[&1]))

      {:ok,
       %{
         subject: subject,
         html: html_body(html, markdown, text, variables),
         text: text_body(text, markdown, html, variables),
         group: group(config, parts.layout)
       }}
    end
  end

  defp html_body(html, _markdown, _text, _variables) when is_binary(html), do: html

  defp html_body(nil, markdown, _text, variables) when is_binary(markdown),
    do: present(Markdown.to_html(markdown, variables))

  defp html_body(nil, nil, text, _variables) when is_binary(text), do: Layout.text_to_html(text)
  defp html_body(nil, nil, nil, _variables), do: nil

  defp text_body(text, _markdown, _html, _variables) when is_binary(text), do: text

  defp text_body(nil, markdown, _html, variables) when is_binary(markdown),
    do: present(Markdown.to_text(markdown, variables))

  defp text_body(nil, nil, html, _variables) when is_binary(html),
    do: present(HtmlText.to_text(html))

  defp text_body(nil, nil, nil, _variables), do: nil

  defp group(%Config{layout_group: default}, layout) do
    if is_binary(layout) and Layout.valid_group?(layout), do: layout, else: default
  end

  defp lorem do
    %{
      subject: @lorem_subject,
      html: Layout.text_to_html(@lorem_text),
      text: @lorem_text,
      group: nil
    }
  end

  defp finish(%Config{root: root}, %{subject: subject, html: html, text: text}, group, locale) do
    if is_nil(html) or Layout.document?(html) do
      {subject, html, text}
    else
      with :ok <- check_chrome(root, group, locale) do
        {subject, Layout.wrap(html, subject, group: group, locale: locale, paths: [root]), text}
      end
    end
  end

  ## Checks

  defp check_sources(root, sources) do
    Enum.reduce_while(sources, :ok, fn
      {_part, {:file, path}}, :ok -> check_file(root, path)
      {_part, _default}, :ok -> {:cont, :ok}
    end)
  end

  @doc """
  The template names whose files `PhoenixKit.Email.Layout.wrap/3` reads
  for `group` (`nil` — the shared chrome only): each chrome part of the
  group, then the shared one.
  """
  @spec chrome_names(String.t() | nil) :: [String.t()]
  def chrome_names(group) do
    for base <- [Layout.name(), Layout.header_name(), Layout.footer_name()],
        name <- if(group, do: ["#{base}-#{group}", base], else: [base]),
        do: name
  end

  # The files `Layout.wrap/3` would read, by the language's chain — their
  # directories checked before the lookup reads any of them.
  defp check_chrome(root, group, locale) do
    names = chrome_names(group)

    with :ok <- check_templates(root, names) do
      Enum.reduce_while(names, :ok, &check_located(root, &1, locale, &2))
    end
  end

  defp check_located(root, name, locale, :ok) do
    case Overrides.locate([root], name, :html, locale) do
      {path, _content} -> check_file(root, path)
      nil -> {:cont, :ok}
    end
  end

  @doc """
  `:ok` when each of the templates `names` under `root` passes
  `PhoenixKitTemplatesEditor.Files.check_template/2`, else `{:error,
  message}` naming the first file refused, relative to the root — the
  check a host's preview and "Send to me" go through too, since they read
  the files by the library's lookup.
  """
  @spec check_templates(Path.t(), [String.t()]) :: :ok | {:error, String.t()}
  def check_templates(root, names) do
    Enum.reduce_while(names, :ok, fn name, :ok ->
      case check_template(root, name) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp check_template(root, name) do
    case Files.check_template(root, name) do
      :ok -> :ok
      {:error, {reason, path}} -> refused(root, path, reason)
    end
  end

  defp check_file(root, path) do
    case Files.check(root, path) do
      {:ok, %File.Stat{size: size}} ->
        if size <= Overrides.max_bytes(),
          do: {:cont, :ok},
          else: {:halt, refused(root, path, :too_large)}

      {:error, reason} ->
        {:halt, refused(root, path, reason)}
    end
  end

  defp refused(root, path, :too_large) do
    {:error,
     gettext("%{file} is larger than %{size} KiB: not read.",
       file: Files.relative(root, path),
       size: div(Overrides.max_bytes(), 1024)
     )}
  end

  defp refused(root, path, _unsafe) do
    {:error,
     gettext("%{file} is a link or outside the template directory: not read.",
       file: Files.relative(root, path)
     )}
  end

  defp present(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp present(_value), do: nil
end
