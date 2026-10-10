defmodule PhoenixKitTemplatesEditor.Sources do
  @moduledoc """
  Where each part of an email core sends would come from —
  asked of core's own resolution, `PhoenixKit.Email.Content.resolve_with_sources/5`,
  so the answer is the one a send gets: the Emails module's active database
  template (`:db`, which wins over every file), a file of the root
  (`{:file, path}`; `{:blank_file, path}` for an empty one, which leaves the
  part out), the built-in text of the email's catalogue entry
  (`:default`), or nothing (`nil`) — and what the HTML and text bodies are
  built from (`html_from`, `text_from`: `:html`, `:markdown`, `:text`).

  Only the root the editor shows is looked at; the work runs with a deadline.
  An email the host sends itself does not go through core, so this says
  nothing about it.
  """

  alias PhoenixKit.Email.Content
  alias PhoenixKitTemplatesEditor.Bounded

  @recipient "preview@example.com"
  @parts [:subject, :text, :html, :markdown]

  @type source :: Content.source() | nil
  @type t :: %{
          subject: source(),
          text: source(),
          html: source(),
          markdown: source(),
          html_from: :html | :markdown | :text | nil,
          text_from: :text | :markdown | nil,
          db?: boolean()
        }

  @doc """
  The sources of `name` in `locale` from `root`, with catalogue `entry`'s
  built-in text and layout (`nil` — none).
  """
  @spec of(Path.t(), String.t(), String.t(), map() | nil) :: {:ok, t()} | {:error, String.t()}
  def of(root, name, locale, entry) do
    defaults = defaults(entry)
    opts = [locale: locale, paths: [root], layout: layout(entry)]

    case Bounded.run(fn -> resolve(name, defaults, opts) end) do
      {:ok, result} -> result
      {:error, :timeout} -> {:error, "timeout"}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  catch
    kind, reason -> {:error, Exception.format_banner(kind, reason)}
  end

  defp resolve(name, defaults, opts) do
    {_content, sources} = Content.resolve_with_sources(name, @recipient, %{}, defaults, opts)
    parts = Map.new(@parts ++ [:html_from, :text_from], &{&1, Map.get(sources, &1)})
    {:ok, Map.put(parts, :db?, Enum.any?(@parts, &(parts[&1] == :db)))}
  end

  defp defaults(%{defaults: fun}) when is_function(fun, 0), do: fun
  defp defaults(%{defaults: map}) when is_map(map), do: fn -> map end
  defp defaults(_entry), do: fn -> %{} end

  defp layout(%{layout: layout}) when is_binary(layout) or is_boolean(layout), do: layout
  defp layout(_entry), do: true
end
