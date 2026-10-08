defmodule PhoenixKitTemplatesEditor.HtmlText do
  @moduledoc """
  An HTML email body as plain text — what the editor's *Fill text from
  content* button makes of an HTML part, and the default preview's text
  version of an email that has only HTML. Public: a host may use it for its
  own text bodies. Deliberately small: emails are simple HTML.

  What is not text — `head`, `style`, `title`, `script`, comments — goes
  whole (an unclosed comment, `style`, `title` or `script` to the end, as a
  browser reads it); a paragraph, a heading or a quote is a block of its
  own between blank lines, a list, a `div`, a table or its row starts and
  ends a line, as a line break and the end of a list item do; table cells
  are apart by a space; a list item starts with "- "; a link to an
  `http(s)` or `mailto` address reads "label: address" (the address alone
  when it is its own label, the label alone for any other address); the
  other tags go, the entities are decoded once (one for a control character
  other than a tab or a line break stays as written), runs of spaces become
  one, and there is never more than one blank line in a row. Bytes that are
  not UTF-8 read as U+FFFD. Placeholders (`{{name}}`) are text like any
  other and come through as written.

  No pattern scans the rest of the text again for each unclosed tag: a
  hand-written file with many costs linear time.
  """

  @raw_text ~r{<(style|title|script)\b[^<>]*>.*?(?:</\1\s*>|\z)}is
  @head ~r{<head\b[^<>]*>(?:(?!<(?:head|body)\b).)*?</head\s*>}is
  @comment ~r/<!--.*?(?:-->|\z)/s
  @link ~r{<a\b([^<>]*)>((?:(?!<a\b).)*?)</a\s*>}is
  @href ~r/\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/i
  @tag ~r/<[^>]*>/

  @entities %{
    "amp" => "&",
    "lt" => "<",
    "gt" => ">",
    "quot" => "\"",
    "apos" => "'",
    "nbsp" => " ",
    "ndash" => "–",
    "mdash" => "—",
    "hellip" => "…",
    "laquo" => "«",
    "raquo" => "»",
    "bdquo" => "„",
    "ldquo" => "“",
    "rdquo" => "”",
    "lsquo" => "‘",
    "rsquo" => "’",
    "euro" => "€",
    "copy" => "©",
    "middot" => "·"
  }

  @doc "`html` as plain text."
  @spec to_text(String.t()) :: String.t()
  def to_text(html) when is_binary(html) do
    html
    |> String.replace_invalid()
    |> String.replace(@comment, "")
    |> String.replace(@raw_text, "")
    |> String.replace(@head, "")
    # The source's own line breaks are spaces in HTML.
    |> String.replace(~r/\s+/u, " ")
    |> replace_links()
    |> String.replace(~r{<br\s*/?>}i, "\n")
    |> String.replace(~r{</?(?:p|h[1-6]|blockquote)\b[^>]*>}i, "\n\n")
    |> String.replace(~r{</?(?:div|tr|table|ul|ol)\b[^>]*>}i, "\n")
    |> String.replace(~r{</li\s*>}i, "\n")
    |> String.replace(~r{</t[dh]\s*>}i, " ")
    |> String.replace(~r/<li\b[^>]*>/i, "- ")
    |> String.replace(@tag, "")
    |> decode_entities()
    |> String.split("\n")
    |> Enum.map_join("\n", &(&1 |> String.replace(~r/[ \t]+/, " ") |> String.trim()))
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  defp replace_links(html), do: Regex.replace(@link, html, &link/3)

  # The label and the address stay as HTML here: the tags and the entities
  # of the whole text go once, later. Only the comparison decodes them.
  defp link(_whole, attributes, label) do
    href =
      case Regex.run(@href, attributes, capture: :all_but_first) do
        nil -> ""
        captures -> captures |> Enum.reject(&(&1 == "")) |> List.first("") |> String.trim()
      end

    plain_label = label |> String.replace(@tag, "") |> decode_entities() |> String.trim()
    address = decode_entities(href)

    cond do
      not Regex.match?(~r/\A(?:https?:\/\/|mailto:)\S/i, address) -> label
      plain_label == "" -> href
      address in [plain_label, "mailto:" <> plain_label] -> label
      true -> label <> ": " <> href
    end
  end

  defp decode_entities(text) do
    Regex.replace(~r/&(#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]+);/, text, fn whole, entity ->
      decode(entity) || whole
    end)
  end

  defp decode("#x" <> hex), do: codepoint(String.to_integer(hex, 16))
  defp decode("#X" <> hex), do: codepoint(String.to_integer(hex, 16))
  defp decode("#" <> decimal), do: codepoint(String.to_integer(decimal))
  defp decode(name), do: Map.get(@entities, name)

  defp codepoint(code) when code in 0xD800..0xDFFF or code > 0x10FFFF, do: nil
  defp codepoint(code) when code in [?\t, ?\n, ?\r], do: <<code>>
  defp codepoint(code) when code < 0x20 or code in 0x7F..0x9F, do: nil
  defp codepoint(code), do: <<code::utf8>>
end
