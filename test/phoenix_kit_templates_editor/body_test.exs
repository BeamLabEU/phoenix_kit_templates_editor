defmodule PhoenixKitTemplatesEditor.BodyTest do
  # The body of a letter on its way between the files and the Leaf editor:
  #
  #   * `from_text/1` — a text-only letter opened in Leaf;
  #   * `to_editor/1` / `from_editor/1` — the stored Markdown into Leaf and back,
  #     Leaf's line break (a bare newline) against the email's (an explicit one);
  #   * `restore_placeholders/1` — what Leaf's visual mode does to `{{…}}`.
  #
  # The round trip text → Markdown → text goes through the module's own
  # converter, the one that derives the text file on a save.
  use ExUnit.Case, async: true

  alias PhoenixKit.Email.Markdown
  alias PhoenixKitTemplatesEditor.Body
  alias PhoenixKitTemplatesEditor.Converters

  # What a save of an untouched, text-only letter would derive.
  defp round_trip(text) do
    text |> Body.from_text() |> Body.from_editor() |> then(&Converters.to_text(:markdown, &1))
  end

  describe "restore_placeholders/1: link and image targets" do
    test "a placeholder in a link target, in either case of the hex digits" do
      assert Body.restore_placeholders("[Open](%7B%7Burl%7D%7D)") == "[Open]({{url}})"
      assert Body.restore_placeholders("[Open](%7b%7burl%7d%7d)") == "[Open]({{url}})"
      assert Body.restore_placeholders("[Open](%7B%7burl%7D%7d)") == "[Open]({{url}})"
    end

    test "an image's address" do
      assert Body.restore_placeholders("![Logo](%7B%7Blogo_url%7D%7D)") == "![Logo]({{logo_url}})"
    end

    test "a mailto address" do
      assert Body.restore_placeholders("[Write](mailto:%7B%7Bemail%7D%7D)") ==
               "[Write](mailto:{{email}})"
    end

    test "a placeholder in a query string" do
      assert Body.restore_placeholders("[x](https://a.ee/?id=%7B%7Border.id%7D%7D&b=1)") ==
               "[x](https://a.ee/?id={{order.id}}&b=1)"

      assert Body.restore_placeholders("[x](https://a.ee/%7B%7Border_id%7D%7D/pay)") ==
               "[x](https://a.ee/{{order_id}}/pay)"
    end

    test "three braces stay three" do
      assert Body.restore_placeholders("[x](%7B%7B%7Bhtml_url%7D%7D%7D)") ==
               "[x]({{{html_url}}})"
    end

    test "a target with a title, and several links in a line" do
      assert Body.restore_placeholders(~s<[a](%7B%7Bu%7D%7D "T") and [b](%7B%7Bv%7D%7D)>) ==
               ~s<[a]({{u}} "T") and [b]({{v}})>
    end

    test "a target in angle brackets" do
      assert Body.restore_placeholders("[a](<%7B%7Bu%7D%7D>)") == "[a](<{{u}}>)"
    end

    test "text outside a target is left alone" do
      text = "plain %7B%7Bx%7D%7D text and [a](https://a.ee/ok)"
      assert Body.restore_placeholders(text) == text
    end

    test "a single encoded brace, or unbalanced ones, in a target stay encoded" do
      for target <- [
            "https://a.ee/?q=%7Bx",
            "https://a.ee/%7B%7Bx%7D",
            "https://a.ee/%7B%7B%7Bx%7D%7D"
          ] do
        text = "[a](#{target})"
        assert Body.restore_placeholders(text) == text
      end
    end
  end

  describe "restore_placeholders/1: escapes inside {{…}}" do
    test "an underscore at the edges of a name" do
      assert Body.restore_placeholders("{{\\_x}}") == "{{_x}}"
      assert Body.restore_placeholders("{{x\\_}}") == "{{x_}}"
      assert Body.restore_placeholders("{{\\_x\\_}}") == "{{_x_}}"
      assert Body.restore_placeholders("{{a\\_\\_b}}") == "{{a__b}}"
      assert Body.restore_placeholders("{{{\\_x}}}") == "{{{_x}}}"
      assert Body.restore_placeholders("{{ \\_x }}") == "{{ _x }}"
    end

    test "any escape Leaf puts inside the braces" do
      assert Body.restore_placeholders("{{a\\_b}}") == "{{a_b}}"
      assert Body.restore_placeholders("{{\\_}}") == "{{_}}"
    end

    test "a placeholder in a sentence, several in a line" do
      assert Body.restore_placeholders("Order {{\\_n}} for {{c\\_}}: {{ok}}.") ==
               "Order {{_n}} for {{c_}}: {{ok}}."
    end

    test "an escape outside the braces is left alone" do
      assert Body.restore_placeholders("snake\\_case \\_{{x}}\\_ done") ==
               "snake\\_case \\_{{x}}\\_ done"
    end

    test "braces that are not a placeholder once unescaped are left alone" do
      assert Body.restore_placeholders("{{a\\*b}}") == "{{a\\*b}}"
      assert Body.restore_placeholders("{{two words}}") == "{{two words}}"
    end

    test "both fixes together" do
      assert Body.restore_placeholders("[{{\\_a}}](%7B%7Bb_%7D%7D)") == "[{{_a}}]({{b_}})"
    end

    test "it changes nothing it was not asked to, and is idempotent" do
      text = "Hello **{{name}}**\n\n[a](https://a.ee) {{x_y}}\n"
      assert Body.restore_placeholders(text) == text

      once = Body.restore_placeholders("[a](%7B%7Bu%7D%7D) {{\\_x}}")
      assert Body.restore_placeholders(once) == once
    end
  end

  describe "from_editor/1 and to_editor/1: line breaks" do
    test "a bare newline between two lines of a paragraph becomes an explicit break" do
      assert Body.from_editor("Hi\n\nA\nB\nC\n\nBye") == "Hi\n\nA\\\nB\\\nC\n\nBye"
    end

    test "to_editor undoes it" do
      assert Body.to_editor("Hi\n\nA\\\nB\\\nC\n\nBye") == "Hi\n\nA\nB\nC\n\nBye"
    end

    test "a break written with two trailing spaces is read as a break, too" do
      assert Body.to_editor("A  \nB") == "A\nB"
      assert Body.from_editor("A  \nB") == "A  \nB"
    end

    test "a break already explicit is not marked again" do
      assert Body.from_editor("A\\\nB") == "A\\\nB"
    end

    test "trailing spaces of a line that gets a break are dropped" do
      assert Body.from_editor("A \nB") == "A\\\nB"
    end

    test "a backslash that is a character, not a break, is kept and the break added" do
      assert Body.from_editor("path\\\\\nnext") == "path\\\\\\\nnext"
      assert Body.to_editor("path\\\\\\\nnext") == "path\\\\\nnext"
      assert Body.to_editor("path\\\\\nnext") == "path\\\\\nnext"
    end

    test "no break at the end of a paragraph, before a blank line, or at the end" do
      assert Body.from_editor("A\n\nB\n") == "A\n\nB\n"
      assert Body.from_editor("A\\\n\nB") == "A\\\n\nB"
    end

    test "no break around blocks" do
      for text <- [
            "- a\n- b",
            "1. a\n2. b",
            "# Title\ntext",
            "text\n# Title",
            "text\n> quote",
            "text\n- item",
            "| a | b |\n| - | - |\n| 1 | 2 |",
            "a | b\n--- | ---\n1 | 2",
            "text\n---",
            "text\n***",
            "Title\n=====",
            "text\n<div>x</div>"
          ] do
        assert Body.from_editor(text) == text
      end
    end

    test "lines of one quotation get a break, and a line of an address or a link is a line" do
      assert Body.from_editor("> a\n> b\n> - c\n> d") == "> a\\\n> b\n> - c\\\n> d"
      assert Body.to_editor("> a\\\n> b") == "> a\n> b"

      assert Body.from_editor("<https://x.ee/a>\ntext\n<a@b.ee>\nmore") ==
               "<https://x.ee/a>\\\ntext\\\n<a@b.ee>\\\nmore"

      assert Body.from_editor("text\n<div>x</div>\n<!-- c -->") ==
               "text\n<div>x</div>\n<!-- c -->"
    end

    test "a nested list item gets no break on its parent's line, at any depth" do
      for text <- [
            "- a\n  - b\n    - c",
            "- a\n    - b",
            "1. a\n   - b\n     - c",
            "1. a\n   1. b\n      1. c",
            "- a\n  1. b\n     - c\n- d"
          ] do
        assert Body.from_editor(text) == text
        assert Body.to_editor(text) == text
      end
    end

    test "the second and later lines of a nested item keep their breaks" do
      text = "- a\n  - b\n    more\n    more2\n  - c"
      assert Body.from_editor(text) == "- a\n  - b\\\n    more\\\n    more2\n  - c"
      assert Body.to_editor(Body.from_editor(text)) == text
      refute Markdown.to_html(Body.from_editor(text), %{}) =~ "\\"
    end

    test "an indented line after a blank line is still code, not a continuation" do
      text = "- a\n\n    code\n    more"
      assert Body.from_editor(text) == text
    end

    test "a line continued in a nested item still gets its break; the item after does not" do
      text = "- a\n  - b\n    more\n  - c"
      assert Body.from_editor(text) == "- a\n  - b\\\n    more\n  - c"
    end

    test "a fenced code block is left alone, and the line after it too" do
      text = "Before\n\n```\none\ntwo\n```\nafter\nmore"
      assert Body.from_editor(text) == "Before\n\n```\none\ntwo\n```\nafter\\\nmore"
      assert Body.to_editor(Body.from_editor(text)) == text
    end

    test "a line continued in a list item" do
      assert Body.from_editor("- first\n  more\n- second") == "- first\\\n  more\n- second"
    end

    test "the two directions are inverse for ordinary text, and idempotent" do
      text = "Tere!\n\nA\nB\n{{x}} | {{y}}\n\nBye\n"
      assert Body.to_editor(Body.from_editor(text)) == text
      assert Body.from_editor(Body.from_editor(text)) == Body.from_editor(text)
      assert Body.to_editor(Body.to_editor(text)) == text
    end

    test "Windows line ends are read as Unix ones" do
      assert Body.from_editor("A\r\nB\r\n\r\nC") == "A\\\nB\n\nC"
    end

    test "from_editor also restores the placeholders" do
      assert Body.from_editor("[Open](%7B%7Burl%7D%7D)\nline {{\\_x}}") ==
               "[Open]({{url}})\\\nline {{_x}}"
    end

    test "an empty body" do
      assert Body.from_editor("") == ""
      assert Body.to_editor("") == ""
    end
  end

  describe "from_text/1" do
    test "blank lines at the ends go, a run of them between two paragraphs stays" do
      assert Body.from_text("\n\nTere!\n\n\n\nParimat\n\n") == "Tere!\n\n\n\nParimat"
      assert Body.room?("Tere!\n\n\n\nParimat")
      refute Body.room?("Tere!\n\nParimat\n\n\n")
    end

    test "keeping_room/2 converts each stretch and puts the runs back" do
      upcase = fn stretch -> {:ok, String.upcase(stretch)} end
      assert Body.keeping_room("a\n \n\n\nb\nc", upcase) == {:ok, "A\n\n\n\nB\nC"}
      assert Body.keeping_room("a\n\n\nb", fn _ -> {:error, :down} end) == {:error, :down}
    end

    test "paragraphs, and single line breaks kept as they are" do
      text = "Tere!\n\nBody.\n\nLugupidamisega\n{{designer_name}}\nDisainer-konsultant, ACME"

      assert Body.from_text(text) == text
    end

    test "Windows line ends, indentation and trailing spaces do not reach the Markdown" do
      assert Body.from_text("A  \r\n   B\t\r\n\r\n  C") == "A\nB\n\nC"
    end

    test "nothing in a blank text" do
      assert Body.from_text("") == ""
      assert Body.from_text(" \n\t\n") == ""
    end

    test "Markdown marks in the text are escaped" do
      assert Body.from_text("2 * 3, *bold*, a*b*c, `code`, [x](y), ![i](u), <b>, ~~s~~") ==
               "2 \\* 3, \\*bold\\*, a\\*b\\*c, \\`code\\`, \\[x](y), !\\[i](u), \\<b>, \\~\\~s\\~\\~"
    end

    test "lines that start like a block are escaped" do
      assert Body.from_text("- a\n+ b\n* c\n# d\n> e\n1. f\n12) g\n=== \n--") ==
               "\\- a\n\\+ b\n\\* c\n\\# d\n\\> e\n1\\. f\n12\\) g\n\\===\n\\-\\-"
    end

    test "placeholders are left alone, whatever their names hold" do
      assert Body.from_text("{{order_number}} {{_x}} {{x_}} {{{items_table}}} {{ a_b }}") ==
               "{{order_number}} {{_x}} {{x_}} {{{items_table}}} {{ a_b }}"
    end

    test "an underscore is escaped unless it stands between two letters or digits" do
      assert Body.from_text("snake_case _lead trail_ __init__ a_1 {{x}}_y") ==
               "snake_case \\_lead trail\\_ \\_\\_init\\_\\_ a_1 {{x}}\\_y"
    end

    test "quotes, dashes and dots that a Markdown renderer would make typographic are escaped" do
      assert Body.from_text("\"x\" 'y' a -- b --- c ... d .... e - f") ==
               "\\\"x\\\" \\'y\\' a \\-\\- b \\-\\-\\- c \\... d \\.\\... e - f"
    end

    test "an entity written in the text is escaped, a lone ampersand is not" do
      assert Body.from_text("&amp; &#38; &copy; and A & B and &x") ==
               "\\&amp; \\&#38; \\&copy; and A & B and &x"
    end

    test "a table-looking line has no dash left to make a table of" do
      assert Body.from_text("a | b\n:-|-:") == "a | b\n:\\-|\\-:"
    end

    test "backslashes" do
      assert Body.from_text("C:\\dir\\ and end\\") == "C:\\\\dir\\\\ and end\\\\"
    end
  end

  describe "from_text/1 then from_editor/1 then the derived text" do
    @exact [
      "Tere, {{customer_name}}!\n\nKirjale on lisatud:\n{{documents_list}}\n\nPalun vaadake.\n\n" <>
        "Lugupidamisega\n{{designer_name}}\nDisainer-konsultant, ACME\n{{designer_phone}} | {{designer_email}}",
      "Здравствуйте!\n\nПросим принять заказ № {{order_number}}. Артикулы и количество — в вложении:\n" <>
        "{{documents_list}}\n\nС уважением,\n{{designer_name}}\nACME",
      "Dear {{customer_name}},\n\nThank you — your reply will come directly to me.\n\nKind regards,\n{{designer_name}}",
      "{{{items_table}}}",
      "Before\n\n{{{items_table}}}\n\nAfter",
      "Items:\n{{{items_table}}}\nTotal: {{total}}",
      "{{documents_list}}",
      "- one\n- two\n+ three\n* four\n-five\n+six\n*seven",
      "1. one\n2. two\n12) twelve\n2026. aastal\n3.14 is pi",
      "# not a heading\n> not a quote\n#hashtag\n>> deeper",
      "a\n---\nb\n===\n***\n___\n- - -\n--",
      "snake_case _lead trail_ __init__ a_1 _x_ __y__ {{x}}_y_{{z}}",
      "2 * 3 = 6; *bold*; **strong**; a*b*c; ***both***; * alone",
      "info@example.com, {{user}}@example.com, <not@a.tag>, mailto:x@y.ee",
      "a | b\nc | d | e\n| lead\ntrail |\n|---|---|\n--- | ---\n:-|-:",
      "back\\slash, `tick`, [text](url), ![alt](src), [ref]: http://x, <b>bold</b>, <https://a.ee>",
      "&amp; &lt;b&gt; &#38; &copy; A & B x&y",
      "~~strike~~ ~one~ ^sup^ $math$ :smile:",
      "\"quoted\" 'single' don't -- dash --- long ... dots .... more - minus",
      "https://example.com/a_b?x=1&y=2 www.example.com http://x.ee/~user/a*b",
      "Kõik on korras: ä ö ü õ — € ✓ 😀 tab\there",
      "word\u00A0nbsp and  two  spaces",
      "Line with trailing backslash\\\nnext",
      "A\nB\nC\nD",
      "",
      "x"
    ]

    for {text, index} <- Enum.with_index(@exact) do
      test "an ordinary letter comes back exactly (#{index})" do
        text = unquote(text)
        assert round_trip(text) == text
      end
    end

    test "Windows line ends come back as Unix ones" do
      assert round_trip("A\r\nB\r\n\r\nC") == "A\nB\n\nC"
    end
  end

  describe "where the round trip is not exact" do
    # The cases `from_text/1` documents: what a Markdown paragraph cannot keep.
    test "several blank lines in a row come back as one" do
      assert round_trip("Tere!\n\n\n\nLugupidamisega") == "Tere!\n\nLugupidamisega"
    end

    test "trailing spaces, and the indentation of a line, are dropped" do
      assert round_trip("a  \n    b\n\tc") == "a\nb\nc"
    end

    test "the blank lines around the text, and the final newline, are dropped" do
      assert round_trip("\n\nA\n\n") == "A"
    end

    test "a line of spaces is a blank line" do
      assert round_trip("A\n   \nB") == "A\n\nB"
    end
  end

  describe "a placeholder that stands for a block" do
    @blocks ["documents_list"]

    # What the host's send does with the line of such a placeholder: the block
    # takes its place with a blank line each side, the line's own break eaten.
    defp fill(markdown, list) do
      Regex.replace(
        ~r/\n?[ \t]*\{\{documents_list\}\}[ \t]*\n?/,
        markdown,
        "\n\n" <> list <> "\n\n"
      )
    end

    # The host's own marker rule: the placeholder with the blanks around it and
    # one line break each side, replaced by the block set apart by blank lines.
    defp host_fill(markdown, list) do
      Regex.replace(
        ~r/\n?(?<![ \t])[ \t]*\{\{\s*documents_list\s*\}\}[ \t]*\n?/,
        markdown,
        "\n\n" <> list <> "\n\n"
      )
    end

    defp html(markdown) do
      markdown |> Markdown.to_html(%{}) |> String.replace(~r/<\/?p[^>]*>/, "")
    end

    for {name, text} <- [
          {"in the middle, after a label line", "Label:\n{{documents_list}}\n\nNext"},
          {"at the start", "{{documents_list}}\nNext\nline"},
          {"at the end", "Hello\nWorld\n{{documents_list}}"},
          {"in the middle of lines", "Hello\n{{documents_list}}\nBye\nnow"},
          {"two in a row", "Hello\n{{documents_list}}\n{{documents_list}}\nBye"},
          {"alone", "Hello\n\n{{documents_list}}\n\nBye"}
        ] do
      test "#{name}: no break beside it, the text version is the text, the letter shows no backslash" do
        text = unquote(text)
        markdown = Body.from_editor(Body.from_text(text), @blocks)

        refute markdown =~ ~r/\\\n[ ]*\{\{/
        refute markdown =~ ~r/\}\}[ ]*\\\n/

        derived = Body.from_editor(Body.from_text(text))
        assert Converters.to_text(:markdown, derived) == text

        filled =
          markdown
          |> String.replace(~r/\{\{\s*documents_list\s*\}\}/, "{{documents_list}}")
          |> fill("- a.pdf\n- b.pdf")

        rendered = html(filled)
        refute rendered =~ "\\"
        assert rendered =~ ~r/<li>\s*a\.pdf\s*<\/li>/
      end
    end

    test "a label line keeps its break from the line before it" do
      assert Body.from_editor("A\nB\n{{documents_list}}\nC\nD", @blocks) ==
               "A\\\nB\n{{documents_list}}\nC\\\nD"
    end

    test "without the list every line break is kept" do
      assert Body.from_editor("A\n{{documents_list}}\nC") == "A\\\n{{documents_list}}\\\nC"
    end

    test "a placeholder in the middle of a line, or of another variable, leaves the breaks alone" do
      assert Body.from_editor("A\nsee {{documents_list}} now\nC\n{{order_number}}\nD", @blocks) ==
               "A\\\nsee {{documents_list}} now\\\nC\\\n{{order_number}}\\\nD"
    end

    test "no break after a line that ends with the placeholder, none before one that starts with it" do
      assert Body.from_editor("Tere\n{{documents_list}} - manused\nHead", @blocks) ==
               "Tere\n{{documents_list}} - manused\\\nHead"

      assert Body.from_editor("Manused: {{documents_list}}\nHead aega", @blocks) ==
               "Manused: {{documents_list}}\nHead aega"

      assert Body.from_editor("A\nB: {{documents_list}}\n{{documents_list}} x\nC", @blocks) ==
               "A\\\nB: {{documents_list}}\n{{documents_list}} x\\\nC"
    end

    test "a placeholder in a quotation counts at the edge of the quoted text" do
      assert Body.from_editor("> a\n> {{documents_list}}\n> c", @blocks) ==
               "> a\n> {{documents_list}}\n> c"
    end

    for {name, text} <- [
          {"text before it on its line", "Tere\n{{documents_list}} - manused\nHead"},
          {"a label before it", "Manused: {{documents_list}}\nHead aega"},
          {"text both sides", "Hello\nWorld: {{documents_list}} (see)\nBye\nnow"}
        ] do
      test "#{name}: the letter shows no backslash and no stray break, the text is the text" do
        text = unquote(text)
        markdown = Body.from_editor(Body.from_text(text), @blocks)

        derived = Body.from_editor(Body.from_text(text))
        assert Converters.to_text(:markdown, derived) == text

        filled = host_fill(markdown, "- a.pdf\n- b.pdf")
        rendered = Markdown.to_html(filled, %{})

        refute rendered =~ "\\"
        refute rendered =~ ~r/<p[^>]*>\s*<br/
        refute rendered =~ ~r/<br[^>]*>\s*<\/p>/
        assert rendered =~ ~r/<li>[\s\S]*a\.pdf/
      end
    end

    test "the stored Markdown is opened as it was typed" do
      text = "Label:\n{{documents_list}}\nNext"
      stored = Body.from_editor(text, @blocks)
      assert Body.to_editor(stored) == text
      assert Body.from_editor(Body.to_editor(stored), @blocks) == stored
    end
  end

  describe "a nested list, as the letter is sent" do
    for {name, leaf} <- [
          {"bullets, two levels", "- a\n  - b\n- c"},
          {"bullets, three levels", "- a\n  - b\n    - c"},
          {"numbers, two levels", "1. a\n   1. b\n2. c"},
          {"numbers over bullets", "1. a\n   - b\n     - c"}
        ] do
      test "#{name} shows no backslash in the HTML or the text" do
        markdown = Body.from_editor(unquote(leaf))
        assert markdown == unquote(leaf)

        refute Markdown.to_html(markdown, %{}) =~ "\\"
        refute Markdown.to_text(markdown, %{}) =~ "\\"
      end
    end

    test "an item that continues on a line of its own keeps that break, with no backslash shown" do
      markdown = Body.from_editor("- a\n  more\n- b")
      assert markdown == "- a\\\n  more\n- b"

      html = Markdown.to_html(markdown, %{})
      assert html =~ ~r/<li>a<br\s*\/?>\s*more<\/li>/
      refute html =~ "\\"
      refute Markdown.to_text(markdown, %{}) =~ "\\"
    end
  end

  describe "large input" do
    @large 256 * 1024

    defp within(milliseconds, fun) do
      {microseconds, _result} = :timer.tc(fun)
      assert microseconds < milliseconds * 1000, "took #{div(microseconds, 1000)} ms"
    end

    defp large(:blanks), do: "a" <> String.duplicate(" ", @large) <> "x"
    defp large(:tabs), do: "a" <> String.duplicate("\t", @large) <> "x"
    defp large(:backslashes), do: String.duplicate("\\", @large)
    defp large(:dashes), do: String.duplicate("-", @large) <> "x"
    defp large(:dash_blanks), do: "-" <> String.duplicate(" -", div(@large, 2)) <> "x"
    defp large(:table), do: "|" <> String.duplicate("-|", div(@large, 2)) <> "x"
    defp large(:delimiter_blanks), do: "|--" <> String.duplicate(" ", @large) <> "x"
    defp large(:braces), do: String.duplicate("{{a", div(@large, 3))
    defp large(:links), do: String.duplicate("](", div(@large, 2))
    defp large(:marks), do: String.duplicate("a_*&", div(@large, 4))
    defp large(:lines), do: String.duplicate("a\n", div(@large, 2))
    defp large(:quotes), do: String.duplicate("> a\n", div(@large, 4))

    for kind <-
          ~w(blanks tabs backslashes dashes dash_blanks table delimiter_blanks braces links marks lines quotes)a do
      test "#{kind}: every function takes a limit's worth in seconds, not minutes" do
        input = large(unquote(kind))

        within(5000, fn -> Body.from_text(input) end)
        within(5000, fn -> Body.from_editor(input) end)
        within(5000, fn -> Body.from_editor(input, ["documents_list"]) end)
        within(5000, fn -> Body.to_editor(input) end)
        within(5000, fn -> Body.restore_placeholders(input) end)
      end
    end
  end
end
