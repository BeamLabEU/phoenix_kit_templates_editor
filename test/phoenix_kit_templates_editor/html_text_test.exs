defmodule PhoenixKitTemplatesEditor.HtmlTextTest do
  # The plain text of an HTML email body: line breaks where the HTML breaks
  # lines, a link as "label: address", the tags gone, the entities decoded,
  # what is not text (head, style, title, script) dropped whole.
  use ExUnit.Case, async: true

  alias PhoenixKitTemplatesEditor.HtmlText

  test "paragraphs, line breaks and headings" do
    html = """
    <h1>Pakkumine</h1>
    <p>Tere,
       Mari!</p><p>Rida üks<br>rida kaks<br/>rida kolm</p>
    """

    assert HtmlText.to_text(html) == "Pakkumine\n\nTere, Mari!\n\nRida üks\nrida kaks\nrida kolm"
  end

  test "list items start with a dash, one per line" do
    assert HtmlText.to_text(
             "<p>Lisatud:</p><ul>\n<li>a.pdf</li>\n<li>b.pdf</li>\n</ul><p>Aitäh</p>"
           ) ==
             "Lisatud:\n\n- a.pdf\n- b.pdf\n\nAitäh"
  end

  test "a link reads label: address; the address alone when it is its own label" do
    assert HtmlText.to_text(~s(<p>See <a href="https://example.com/a?b=1&amp;c=2">here</a>.</p>)) ==
             "See here: https://example.com/a?b=1&c=2."

    assert HtmlText.to_text(~s(<a href='https://www.example.com'>https://www.example.com</a>)) ==
             "https://www.example.com"

    assert HtmlText.to_text(~s(<a href="mailto:info@example.com">info@example.com</a>)) ==
             "info@example.com"

    # Not an address a reader can follow: the label alone.
    assert HtmlText.to_text(~s|<a href="javascript:alert(1)">click</a>|) == "click"
    assert HtmlText.to_text(~s(<a name="top">Up</a>)) == "Up"
  end

  test "tags gone, entities decoded once, spaces collapsed" do
    assert HtmlText.to_text(
             "<div><b>Mööbel</b>   &amp; <i>köök</i>&nbsp;&lt;3&gt; &#8211; &#x20AC;5 &amp;lt;</div>"
           ) == "Mööbel & köök <3> – €5 &lt;"
  end

  test "head, style, title, script and comments are dropped whole" do
    html = """
    <!DOCTYPE html>
    <html><head><title>Subject</title><style>p { color: red; }</style></head>
    <body><!-- note --><script>alert(1)</script><p>Hello!</p></body></html>
    """

    assert HtmlText.to_text(html) == "Hello!"
  end

  test "placeholders are text" do
    assert HtmlText.to_text("<p>Hello, {{customer_name}}!</p><p>{{documents_list}}</p>") ==
             "Hello, {{customer_name}}!\n\n{{documents_list}}"
  end

  test "never more than one blank line in a row" do
    assert HtmlText.to_text("<p>a</p><p></p><p> </p><br><br><br><p>b</p>") == "a\n\nb"
  end

  test "table cells apart" do
    assert HtmlText.to_text(
             "<table><tr><td>A</td><td>B</td></tr><tr><th>C</th><th>D</th></tr></table>"
           ) == "A B\n\nC D"
  end

  test "an entity for a control character other than a tab or a line break stays as written" do
    assert HtmlText.to_text("a&#1;b&#x7F;c&#9;d") == "a&#1;b&#x7F;c d"
  end

  test "bytes that are not UTF-8 read as replacement characters" do
    assert HtmlText.to_text(<<"<p>a", 255, "b</p>">>) == "a�b"
  end

  test "unclosed tags take linear time" do
    for open <- ["<a ", "<a>", "<a href='https://x'>", "<style>", "<head x>", "<!--"] do
      html = String.duplicate(open <> "x ", 20_000)
      {micros, text} = :timer.tc(fn -> HtmlText.to_text(html) end)
      assert is_binary(text)
      assert micros < 2_000_000, "#{open}: #{div(micros, 1000)} ms"
    end

    long = String.duplicate("word ", 200_000)

    for open <- ["<a href='https://x'>", "<head>", "<style>", "<!--"] do
      assert is_binary(HtmlText.to_text(open <> long <> "<p>x</p>"))
    end
  end
end
