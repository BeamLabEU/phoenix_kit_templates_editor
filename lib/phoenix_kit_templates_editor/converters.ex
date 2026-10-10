defmodule PhoenixKitTemplatesEditor.Converters do
  @moduledoc """
  The converters behind the editor's buttons (`convert:` of
  `PhoenixKitTemplatesEditor.Web.Editor`): *Fill text from content* —
  `to_text/3`, Markdown as `PhoenixKit.Email.Markdown` makes an email's
  text, HTML as `PhoenixKitTemplatesEditor.HtmlText` does — and *Markdown →
  HTML* — `markdown_to_html/2`, with the accent colour of
  `PhoenixKit.Email.Branding` written in, as an email from that Markdown
  would have it then.

  The placeholders come back as typed, for the email to fill when it is
  sent. A renderer given no value for one drops a link to it (only an
  `http(s)` or `mailto` address is kept), so each distinct placeholder
  travels as an address of its own — `https://pk<nonce>.invalid/<n>x`,
  absent from the source — and is put back afterwards; `{{ x }}` comes back
  as `{{x}}`, `{{{x}}}` stays three braces.

  ## Limits

  A source over `PhoenixKit.Templates.Overrides.max_bytes/0` — more than a
  template file may hold — is `{:error, :too_large}` before any work. The
  work runs in a task with a deadline (`:timeout`, 5 s by default); past it,
  `{:error, :timeout}`. No pattern here retries at every position of a run
  of spaces: a source of the largest size converts in linear time.
  """

  alias PhoenixKit.Email.Branding
  alias PhoenixKit.Email.Markdown
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Bounded
  alias PhoenixKitTemplatesEditor.HtmlText

  # The placeholder grammar of `PhoenixKit.Templates.Substitution`. Each
  # alternative starts with literal braces, so a run of spaces is scanned
  # once per brace pair, never again from each space.
  @placeholder ~r/\{\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}\}|\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}/

  @type option :: {:timeout, timeout()} | {:block_placeholders, [String.t()]}
  @type result :: String.t() | {:error, :too_large | :timeout}

  @doc """
  `source` (`:markdown` or `:html`) as plain text, its placeholders as
  written. Options: `:timeout`.
  """
  @spec to_text(:markdown | :html, String.t(), [option()]) :: result()
  def to_text(format, source, opts \\ [])

  def to_text(:markdown, markdown, opts) when is_binary(markdown) do
    bounded(markdown, opts, fn ->
      {protected, variables, tokens} = protect_as_variables(markdown)
      protected |> Markdown.to_text(variables) |> restore(tokens)
    end)
  end

  def to_text(:html, html, opts) when is_binary(html) do
    bounded(html, opts, fn ->
      {protected, tokens} = protect_in_place(html)
      protected |> HtmlText.to_text() |> restore(tokens)
    end)
  end

  @doc """
  `markdown` as the HTML an email makes of it — the accent colour of
  `PhoenixKit.Email.Branding` written in — its placeholders as written.

  Options:

    * `:block_placeholders` — names of variables that hold a block of their
      own (a list, a table): such a placeholder alone in a paragraph is left
      bare, outside the `<p>`, since the block a send puts there may not
      stand inside one.
    * `:timeout`.
  """
  @spec markdown_to_html(String.t(), [option()]) :: result()
  def markdown_to_html(markdown, opts \\ []) when is_binary(markdown) do
    blocks = Keyword.get(opts, :block_placeholders, [])

    bounded(markdown, opts, fn ->
      {protected, variables, tokens} = protect_as_variables(markdown)

      protected
      |> Markdown.to_html(Map.put(variables, "accent_color", Branding.accent_color()))
      |> restore(tokens)
      |> unwrap_blocks(blocks)
    end)
  end

  defp bounded(source, opts, fun) do
    if byte_size(source) > Overrides.max_bytes() do
      {:error, :too_large}
    else
      case Bounded.run(fun, Keyword.get(opts, :timeout, 5_000)) do
        {:ok, result} -> result
        {:error, :timeout} -> {:error, :timeout}
      end
    end
  end

  # A paragraph that is one block placeholder alone: the placeholder without
  # the paragraph. The paragraph's own attributes stop at the first `>` or
  # `<`, and the spaces around the placeholder are taken possessively, so
  # each paragraph is scanned once.
  defp unwrap_blocks(html, []), do: html

  defp unwrap_blocks(html, names) do
    alternatives = Enum.map_join(names, "|", &Regex.escape/1)

    ~r/<p(?:\s[^<>]*+)?>[ \t\r\n]*+(\{\{(?:#{alternatives})\}\})[ \t\r\n]*+<\/p>/
    |> Regex.replace(html, "\\1")
  end

  # Each placeholder becomes a variable of its own whose value is the token
  # (`{{pk<nonce>v<n>}}`, three braces kept), so the renderer substitutes the
  # token where it would the value — a link's target included.
  defp protect_as_variables(source) do
    tokens = tokens(source)

    protected =
      Regex.replace(@placeholder, source, fn whole, _raw, _name ->
        %{variable: variable, raw?: raw?} = Map.fetch!(tokens.by_placeholder, normalize(whole))
        if raw?, do: "{{{#{variable}}}}", else: "{{#{variable}}}"
      end)

    variables =
      Map.new(tokens.by_placeholder, fn {_placeholder, %{variable: variable, token: token}} ->
        {variable, token}
      end)

    {protected, variables, tokens}
  end

  # HTML is not rendered, only read: each placeholder is its token in place.
  defp protect_in_place(source) do
    tokens = tokens(source)

    protected =
      Regex.replace(@placeholder, source, fn whole, _raw, _name ->
        Map.fetch!(tokens.by_placeholder, normalize(whole)).token
      end)

    {protected, tokens}
  end

  defp tokens(source) do
    nonce = nonce(source)

    by_placeholder =
      @placeholder
      |> Regex.scan(source, capture: :first)
      |> Enum.map(fn [whole] -> normalize(whole) end)
      |> Enum.uniq()
      |> Enum.with_index()
      |> Map.new(fn {placeholder, index} ->
        {placeholder,
         %{
           token: "https://pk#{nonce}.invalid/#{index}x",
           variable: "pk#{nonce}v#{index}",
           raw?: String.starts_with?(placeholder, "{{{")
         }}
      end)

    %{
      by_placeholder: by_placeholder,
      by_token:
        Map.new(by_placeholder, fn {placeholder, %{token: token}} -> {token, placeholder} end),
      pattern: Regex.compile!("https://pk#{nonce}\\.invalid/[0-9]+x")
    }
  end

  defp restore(converted, tokens),
    do: Regex.replace(tokens.pattern, converted, &Map.get(tokens.by_token, &1, &1))

  defp normalize(placeholder) do
    case Regex.run(@placeholder, placeholder) do
      [_whole, raw] -> "{{{#{raw}}}}"
      [_whole, "", name] -> "{{#{name}}}"
    end
  end

  defp nonce(source) do
    nonce = 6 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
    if String.contains?(source, "pk" <> nonce), do: nonce(source), else: nonce
  end
end
