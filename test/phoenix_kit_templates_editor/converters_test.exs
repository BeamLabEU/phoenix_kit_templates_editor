defmodule PhoenixKitTemplatesEditor.ConvertersTest do
  # The converters behind the editor's buttons: *Fill text from content*
  # (`to_text/2`) and *Markdown → HTML* (`markdown_to_html/2`). The
  # placeholders come back as typed — in a link's target too, which a
  # renderer with no variables would drop — for the email to fill when it is
  # sent. Settings are not read from a database here: the accent colour is
  # core's default (see the integration test for a configured one).
  use ExUnit.Case, async: true

  alias PhoenixKit.Email.Branding
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Converters

  describe "markdown_to_html/2" do
    test "the Markdown as HTML, its placeholders kept" do
      html =
        Converters.markdown_to_html("Hello, **{{customer_name}}**!\n\nOrder {{ order_number }}")

      assert html =~ "Hello, <strong>{{customer_name}}</strong>!"
      assert html =~ "Order {{order_number}}"
    end

    test "a link's target and an image's address keep their placeholders" do
      html =
        Converters.markdown_to_html(
          "See [here]({{offer_url}}) and write [to us](mailto:{{designer_email}}).\n\n" <>
            "![Logo]({{site_url}}/images/logo.png)"
        )

      assert html =~ ~s(href="{{offer_url}}")
      assert html =~ ~s(href="mailto:{{designer_email}}")
      assert html =~ ~s(src="{{site_url}}/images/logo.png")
      assert html =~ ">here</a>"
    end

    test "a link alone in its paragraph is a button in the accent colour" do
      html = Converters.markdown_to_html("[Pay]({{payment_url}})")

      assert html =~ ~s(href="{{payment_url}}")
      assert html =~ "background-color:#{Branding.accent_color()}"
    end

    test "three braces stay three, apart from two of the same name" do
      html = Converters.markdown_to_html("{{documents_list}}\n\n{{{documents_list}}}")

      assert html =~ "{{documents_list}}"
      assert html =~ "{{{documents_list}}}"
    end

    test "no placeholders: plain Markdown" do
      assert Converters.markdown_to_html("# Hello") =~ ~r{<h1[^>]*>Hello</h1>}
    end
  end

  describe "markdown_to_html/2 and block placeholders" do
    @blocks [block_placeholders: ["documents_list", "items_table"]]

    test "a block placeholder on a line of its own stands outside any paragraph" do
      html = Converters.markdown_to_html("Hello!\n\n{{documents_list}}\n\nBest", @blocks)

      assert html =~ "{{documents_list}}"
      refute html =~ ~r/<p[^>]*>\s*\{\{documents_list\}\}\s*<\/p>/
      assert html =~ ~r/<p[^>]*>Hello!<\/p>/
      assert html =~ ~r/<p[^>]*>Best<\/p>/
    end

    test "each of them; spaces inside the braces come back bare" do
      html =
        Converters.markdown_to_html("{{ documents_list }}\n\nText\n\n{{items_table}}", @blocks)

      refute html =~ ~r/<p[^>]*>\s*\{\{(documents_list|items_table)\}\}\s*<\/p>/
      assert html =~ "{{documents_list}}"
      assert html =~ "{{items_table}}"
    end

    test "within a sentence it stays in its paragraph" do
      html = Converters.markdown_to_html("Attached: {{documents_list}}", @blocks)

      assert html =~ ~r/<p[^>]*>Attached: \{\{documents_list\}\}<\/p>/
    end

    test "a placeholder not named a block stays in its paragraph" do
      html = Converters.markdown_to_html("{{customer_name}}", @blocks)
      assert html =~ ~r/<p[^>]*>\{\{customer_name\}\}<\/p>/

      html = Converters.markdown_to_html("{{documents_list}}")
      assert html =~ ~r/<p[^>]*>\{\{documents_list\}\}<\/p>/
    end
  end

  describe "to_text/2" do
    test "Markdown as plain text, placeholders and link targets kept" do
      text =
        Converters.to_text(
          :markdown,
          "Hello, **{{customer_name}}**!\n\n[Pay]({{payment_url}})\n\n- {{{documents_list}}}"
        )

      assert text ==
               "Hello, {{customer_name}}!\n\nPay: {{payment_url}}\n\n- {{{documents_list}}}"
    end

    test "HTML as plain text, placeholders and link targets kept" do
      text =
        Converters.to_text(
          :html,
          ~s(<p>Hello, {{customer_name}}!</p><p><a href="{{payment_url}}">Pay</a></p>) <>
            ~s(<p><a href="{{ site_url }}">{{site_url}}</a></p>)
        )

      assert text == "Hello, {{customer_name}}!\n\nPay: {{payment_url}}\n\n{{site_url}}"
    end

    test "a source naming the placeholder token's form is left as written" do
      source = "See https://pk0.invalid/0x and {{x}}"
      assert Converters.to_text(:html, source) == source
    end
  end

  describe "limits" do
    test "a source over the library's file limit is refused before any work" do
      big = String.duplicate("a", Overrides.max_bytes() + 1)

      assert Converters.to_text(:markdown, big) == {:error, :too_large}
      assert Converters.to_text(:html, big) == {:error, :too_large}
      assert Converters.markdown_to_html(big) == {:error, :too_large}
    end

    test "work past the deadline is stopped and reported" do
      big = String.duplicate("**bold** [link](https://example.com) text\n\n", 4_000)

      assert Converters.markdown_to_html(big, timeout: 0) == {:error, :timeout}
      assert Converters.to_text(:markdown, big, timeout: 0) == {:error, :timeout}
    end

    # The largest source a file may hold, built to make a backtracking
    # pattern retry at every position: each conversion stays well within a
    # second.
    test "hostile input of the largest size takes linear time" do
      size = Overrides.max_bytes()

      fill = fn piece ->
        binary_part(String.duplicate(piece, div(size, byte_size(piece)) + 1), 0, size)
      end

      hostile = [
        "{{" <> String.duplicate(" ", size - 2),
        fill.("{{ "),
        fill.("{{{ a"),
        fill.("<p"),
        fill.("<p> "),
        "<p>" <> String.duplicate(" ", size - 3),
        fill.("<a "),
        fill.("[a]("),
        fill.("https://pk0.invalid/"),
        String.duplicate(" ", size)
      ]

      for source <- hostile,
          {name, convert} <- [
            to_text_markdown: &Converters.to_text(:markdown, &1),
            to_text_html: &Converters.to_text(:html, &1),
            markdown_to_html:
              &Converters.markdown_to_html(&1, block_placeholders: ["documents_list"])
          ] do
        {micros, result} = :timer.tc(fn -> convert.(source) end)

        assert is_binary(result),
               "#{name} on #{inspect(binary_part(source, 0, 8))}: #{inspect(result)}"

        assert micros < 1_000_000,
               "#{name} on #{inspect(binary_part(source, 0, 8))}…: #{div(micros, 1000)} ms"
      end
    end

    # Not a pattern of this module: core's Markdown pipeline costs about a
    # second per 256 KiB of emphasis markers, in linear time — within the
    # deadline, not within the patterns' budget above.
    test "the largest source of emphasis markers converts within the deadline" do
      size = Overrides.max_bytes()
      source = binary_part(String.duplicate("*_", div(size, 2) + 1), 0, size)

      assert is_binary(Converters.markdown_to_html(source))
      assert is_binary(Converters.to_text(:markdown, source))
    end
  end
end
