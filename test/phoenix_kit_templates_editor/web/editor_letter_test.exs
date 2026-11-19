defmodule PhoenixKitTemplatesEditor.Web.EditorLetterTest do
  # A letter's body is one Leaf editor (`Web.Letter`): the Markdown file is
  # the body, the text file is derived from it on a save, a text-only letter
  # opens in Leaf as Markdown and nothing is written until Save. Leaf's
  # messages only tell the editor what Leaf holds; the Save event writes.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  alias PhoenixKit.Email.Markdown
  alias PhoenixKit.Templates.Overrides

  @convert %{to_text: {Host, :to_text}, markdown_to_html: {Host, :markdown_to_html}}

  defp read(root, file, name \\ "order_offer"), do: File.read(Path.join([root, name, file]))

  defp files(root, name \\ "order_offer"),
    do: root |> Path.join(name) |> File.ls!() |> Enum.sort()

  defp letter(root, opts \\ %{}) do
    seed(root)
    view = mount_editor(root, opts)
    select(view, "order_offer")
    view
  end

  describe "the form" do
    test "label and subject, then one Leaf; no text, Markdown or HTML field, no conversion buttons",
         %{tmp_dir: root} do
      view = letter(root, %{convert: @convert})

      assert has_element?(view, "#editor-parts textarea[name='parts[label]'][rows='2']")
      assert has_element?(view, "#editor-parts textarea[name='parts[subject]'][rows='2']")
      assert has_element?(view, "#editor-parts #editor-body [phx-hook=Leaf]")

      for part <- ~w(text markdown html) do
        refute has_element?(view, "#editor-parts [name='parts[#{part}]']")
      end

      refute has_element?(view, "#editor-to-text")
      refute has_element?(view, "#editor-md-to-html")
      refute has_element?(view, "#editor-html-note")
    end

    test "Leaf's modes are visual and Markdown: hybrid and HTML are denied", %{tmp_dir: root} do
      view = letter(root)
      html = view |> element("#editor-body") |> render() |> LazyHTML.from_fragment()

      assert LazyHTML.attribute(LazyHTML.query(html, "[phx-hook=Leaf]"), "data-mode") == [
               "visual"
             ]

      for {flag, value} <- [
            html_mode: "true",
            hybrid_mode: "true",
            visual_mode: "false",
            markdown_mode: "false"
          ] do
        attribute = "data-deny-#{String.replace(to_string(flag), "_", "-")}"
        assert LazyHTML.attribute(LazyHTML.query(html, "[phx-hook=Leaf]"), attribute) == [value]
      end
    end

    test "a header, a footer and a layout keep their fields and the hook", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "_header-shop")
      tab(view, "")

      refute has_element?(view, "#editor-body")
      assert has_element?(view, "#editor-parts textarea[name='parts[html]']")
      assert has_element?(view, "#editor-form[phx-hook=PhoenixKitTemplatesEditorInsertVariable]")
    end

    test "read only: the files as they are, no Leaf", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{editable: false})
      select(view, "order_offer")

      refute has_element?(view, "#editor-body")
      assert render(view) =~ "{{documents_list}}"
    end
  end

  describe "opening" do
    test "a Markdown letter opens with its Markdown, an explicit break as a bare newline",
         %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "markdown.et.md", "Tere!\n\nKiri\\\nteine rida\n")
      view = mount_editor(root)
      select(view, "order_offer")

      assert leaf_content(view) == "Tere!\n\nKiri\nteine rida\n"
    end

    test "a text-only letter opens with the text as Markdown, its line breaks kept",
         %{tmp_dir: root} do
      seed(root)

      put(
        root,
        "order_offer",
        "text.et.txt",
        "Tere!\n\nLugupidamisega\n{{designer_name}}\n- Disainer *ACME*\n"
      )

      view = mount_editor(root)
      select(view, "order_offer")

      assert leaf_content(view) ==
               "Tere!\n\nLugupidamisega\n{{designer_name}}\n\\- Disainer \\*ACME\\*"
    end

    test "a blank Markdown file counts as none: the text is used", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "markdown.et.md", " \n")
      view = mount_editor(root)
      select(view, "order_offer")

      assert leaf_content(view) == "Tere!\n\n{{documents_list}}"
    end

    test "a letter without files opens empty", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      create(view, "order_new")

      assert leaf_content(view) == ""
    end

    test "nothing is written by opening, nor by a save with nothing changed", %{tmp_dir: root} do
      view = letter(root)

      assert save(view, %{}) =~ "No changes"

      assert files(root) ==
               ~w(label.en.txt label.et.txt subject.et.txt subject.ru.txt text.et.txt)

      refute_received {:after_write, _paths}
    end

    test "a message that says Leaf is clean writes nothing, whatever it carries",
         %{tmp_dir: root} do
      view = letter(root)

      edit_body(view, "Re-serialised by Leaf", dirty: false)

      assert save(view, %{}) =~ "No changes"
      assert {:error, :enoent} = read(root, "markdown.et.md")
    end

    test "editing and then undoing every edit leaves nothing to write", %{tmp_dir: root} do
      view = letter(root)

      edit_body(view, "Something else")
      edit_body(view, "Tere!\n\n{{documents_list}}", dirty: false)

      assert save(view, %{}) =~ "No changes"
    end

    test "an unreadable body file is shown as such, and no Leaf stands in its place",
         %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "markdown.et.md", <<"Tere ", 0xE4>>)
      view = mount_editor(root)
      select(view, "order_offer")

      refute has_element?(view, "#editor-body")
      assert view |> element("#editor-part-markdown-invalid") |> render() =~ "not valid UTF-8"

      assert save(view, %{subject: "Uus"}) =~ "Saved"
      assert read(root, "markdown.et.md") == {:ok, <<"Tere ", 0xE4>>}
      assert read(root, "text.et.txt") == {:ok, "Tere!\n\n{{documents_list}}\n"}
    end
  end

  describe "saving" do
    test "writes the Markdown and the text derived from it; the final newline stays",
         %{tmp_dir: root} do
      view = letter(root)

      edit_body(view, "Tere **{{order_number}}**!\n\nLugupidamisega\n{{designer_name}}")

      assert save(view, %{}) =~ "Saved"

      assert read(root, "markdown.et.md") ==
               {:ok, "Tere **{{order_number}}**!\n\nLugupidamisega\\\n{{designer_name}}"}

      assert read(root, "text.et.txt") ==
               {:ok, "Tere {{order_number}}!\n\nLugupidamisega\n{{designer_name}}\n"}

      assert_received {:after_write, paths}
      assert length(paths) == 2
    end

    test "a text-only letter that is edited gets a Markdown file; the rest of its text is as it was",
         %{tmp_dir: root} do
      view = letter(root)

      edit_body(view, "Tere!\n\n{{documents_list}}\n\nUus rida")
      save(view, %{})

      assert read(root, "text.et.txt") == {:ok, "Tere!\n\n{{documents_list}}\n\nUus rida\n"}
      assert read(root, "markdown.et.md") == {:ok, "Tere!\n\n{{documents_list}}\n\nUus rida"}
    end

    test "Leaf's damage to placeholders is undone before anything is written", %{tmp_dir: root} do
      view = letter(root)

      edit_body(
        view,
        "[Open](%7B%7Burl%7D%7D) or [write](mailto:%7B%7Bemail%7D%7D)\n\n![Logo](%7B%7Blogo_url%7D%7D) {{\\_a}} {{b\\_}}"
      )

      save(view, %{})

      assert {:ok, markdown} = read(root, "markdown.et.md")

      assert markdown ==
               "[Open]({{url}}) or [write](mailto:{{email}})\n\n![Logo]({{logo_url}}) {{_a}} {{b_}}"
    end

    test "a line break Leaf writes as a newline is an explicit one in the file", %{tmp_dir: root} do
      view = letter(root)

      edit_body(view, "Signature\nline two\nline three\n\n- a\n- b")
      save(view, %{})

      assert read(root, "markdown.et.md") ==
               {:ok, "Signature\\\nline two\\\nline three\n\n- a\n- b"}
    end

    test "the saved letter is rendered with its lines kept", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{preview: :render})
      select(view, "order_offer")

      edit_body(view, "One\nTwo")
      save(view, %{})

      markdown = Templates.render("order_offer", %{}, %{}, locale: "et", paths: [root]).markdown

      assert Markdown.to_html(markdown, %{}) =~ ~r/One<br\s*\/?>\s*Two/
    end

    test "an emptied body deletes both files", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "markdown.et.md", "Tere")
      view = mount_editor(root)
      select(view, "order_offer")

      edit_body(view, "")
      assert save(view, %{}) =~ "Saved"

      assert {:error, :enoent} = read(root, "markdown.et.md")
      assert {:error, :enoent} = read(root, "text.et.txt")
    end

    test "a new letter's first save writes its files", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      create(view, "order_new")

      edit_body(view, "Hello")
      save(view, %{subject: "Subj"})

      assert read(root, "markdown.et.md", "order_new") == {:ok, "Hello"}
      assert read(root, "text.et.txt", "order_new") == {:ok, "Hello"}
      assert read(root, "subject.et.txt", "order_new") == {:ok, "Subj"}
    end

    test "the host's converter makes the text, when it has one", %{tmp_dir: root} do
      view = letter(root, %{convert: @convert})

      edit_body(view, "**Tere**")
      save(view, %{})

      assert read(root, "text.et.txt") == {:ok, "Tere\n"}
    end

    test "a converter that refuses or fails stops the save: nothing is written", %{tmp_dir: root} do
      for to_text <- [
            fn _format, _source -> {:error, "cannot convert this"} end,
            fn _format, _source -> raise "converter down" end
          ] do
        view = letter(root, %{convert: %{to_text: to_text}})
        edit_body(view, "Uus")

        log = capture_log(fn -> assert save(view, %{}) =~ "text version could not be made" end)

        assert is_binary(log)
        assert {:error, :enoent} = read(root, "markdown.et.md")
        assert read(root, "text.et.txt") == {:ok, "Tere!\n\n{{documents_list}}\n"}
      end
    end

    test "a text version too large for a file is refused, nothing is written", %{tmp_dir: root} do
      view = letter(root)

      edit_body(view, String.duplicate("a", Overrides.max_bytes() + 1))
      html = save(view, %{})

      assert html =~ "larger than"
      assert {:error, :enoent} = read(root, "markdown.et.md")
    end

    test "a refused write keeps the body in the form, still unsaved", %{tmp_dir: root} do
      view = letter(root, %{max_root_bytes: 200})
      big = String.duplicate("a", 300)

      doc = leaf_id(view)

      edit_body(view, big)
      assert save(view, %{}) =~ "Not saved"

      # The same Leaf stays, with what the writer typed in it.
      assert leaf_id(view) == doc

      # The same Save again is still an edit to write.
      assert save(view, %{}) =~ "Not saved"
    end

    test "after a save Leaf starts from what is on disk, in the mode the writer chose",
         %{tmp_dir: root} do
      view = letter(root)
      first = leaf_id(view)

      send_mode(view, :markdown)
      edit_body(view, "Uus tekst")
      save(view, %{})

      refute leaf_id(view) == first
      assert leaf_content(view) == "Uus tekst"

      assert view
             |> element("#editor-body [phx-hook=Leaf]")
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.attribute("data-mode") == ["markdown"]
    end
  end

  describe "what a message of Leaf may do" do
    test "an unknown or malformed message is ignored", %{tmp_dir: root} do
      view = letter(root)

      for message <- [
            :nonsense,
            {:leaf_changed, %{}},
            {:leaf_changed, %{editor_id: leaf_id(view), markdown: 42, dirty: true}},
            {:leaf_changed, %{editor_id: leaf_id(view), markdown: <<0xE4>>, dirty: true}},
            {:leaf_mode_changed, %{editor_id: leaf_id(view), mode: :html}},
            {:leaf_flushed, %{editor_id: leaf_id(view), ref: "x", markdown: "x", html: ""}}
          ] do
        send_leaf(view, message)
      end

      assert save(view, %{}) =~ "No changes"
    end

    test "no message writes a file by itself", %{tmp_dir: root} do
      view = letter(root)

      edit_body(view, "Sent by Leaf")

      assert files(root) ==
               ~w(label.en.txt label.et.txt subject.et.txt subject.ru.txt text.et.txt)

      refute_received {:after_write, _paths}
      refute_received {:after_change, _name}
    end

    test "a message of another document is dropped", %{tmp_dir: root} do
      view = letter(root)

      edit_body(view, "From nowhere", doc: "editor-leaf-999")
      edit_body(view, "From a stranger", doc: "other")

      assert save(view, %{}) =~ "No changes"
    end

    test "a message with no letter open changes nothing", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)

      edit_body(view, "Nobody's", doc: "editor-leaf-1")
      select(view, "_header-shop")
      edit_body(view, "Not a letter's", doc: "editor-leaf-2")
      tab(view, "")

      assert save(view, %{}) =~ "No changes"
      assert Process.alive?(view.pid)
    end

    test "a save the host's authorize refuses writes nothing, whatever Leaf said",
         %{tmp_dir: root} do
      view = letter(root, %{authorize: fn _action -> {:error, :nope} end})

      edit_body(view, "Hacked")
      html = save(view, %{})

      assert html =~ "not allowed"
      assert {:error, :enoent} = read(root, "markdown.et.md")
      assert read(root, "text.et.txt") == {:ok, "Tere!\n\n{{documents_list}}\n"}
    end

    test "read only, a save is refused even with a pending body", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")
      edit_body(view, "Pending")
      send(view.pid, {:put, %{editable: false}})
      _ = render(view)

      render_submit(with_target(view, "#editor"), "save", %{"parts" => %{"subject" => "x"}})

      assert {:error, :enoent} = read(root, "markdown.et.md")
      assert read(root, "subject.et.txt") == {:ok, "Pakkumine {{order_number}}\n"}
    end

    test "the form never writes the text, Markdown or HTML a forged submit names",
         %{tmp_dir: root} do
      view = letter(root)

      render_submit(with_target(view, "#editor"), "save", %{
        "parts" => %{
          "subject" => "Muudetud",
          "text" => "forged text",
          "markdown" => "forged md",
          "html" => "<p>forged</p>"
        }
      })

      assert read(root, "subject.et.txt") == {:ok, "Muudetud\n"}
      assert read(root, "text.et.txt") == {:ok, "Tere!\n\n{{documents_list}}\n"}
      assert {:error, :enoent} = read(root, "markdown.et.md")
      assert {:error, :enoent} = read(root, "html.et.html")
    end
  end

  describe "a hand-written HTML file" do
    test "keeps its code field and a note; Leaf edits the Markdown and the HTML is saved on its own",
         %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "html.et.html", "<p>Käsitsi</p>\n")
      view = mount_editor(root)
      select(view, "order_offer")

      assert has_element?(view, "#editor-html-note")
      assert has_element?(view, "#editor-parts textarea[name='parts[html]']")
      assert has_element?(view, "#editor-body [phx-hook=Leaf]")
      refute has_element?(view, "#editor-parts [name='parts[text]']")

      edit_body(view, "Uus")
      save(view, %{html: "<p>Muudetud</p>\n"})

      assert read(root, "html.et.html") == {:ok, "<p>Muudetud</p>\n"}
      assert read(root, "markdown.et.md") == {:ok, "Uus"}
    end

    test "a letter without one has no HTML field", %{tmp_dir: root} do
      view = letter(root)
      refute has_element?(view, "#editor-parts [name='parts[html]']")
    end
  end

  describe "switching with an unsaved body" do
    test "a language switch asks first; staying keeps the text", %{tmp_dir: root} do
      view = letter(root)
      edit_body(view, "Unsaved")

      tab(view, "ru")

      assert has_element?(view, "dialog#editor-confirm-switch #editor-confirm-switch-discard")
      assert has_element?(view, "#editor-languages [aria-pressed=true]", "Eesti")

      view |> element("#editor-confirm-switch-cancel") |> render_click()

      refute has_element?(view, "#editor-confirm-switch")
      assert has_element?(view, "#editor-languages [aria-pressed=true]", "Eesti")
      save(view, %{})
      assert read(root, "markdown.et.md") == {:ok, "Unsaved"}
    end

    test "discarding switches, and the text of one language is never saved into another",
         %{tmp_dir: root} do
      view = letter(root)
      old = leaf_id(view)
      edit_body(view, "Eestikeelne muudatus")

      tab(view, "en")
      view |> element("#editor-confirm-switch-discard") |> render_click()

      assert has_element?(view, "#editor-languages [aria-pressed=true]", "English")
      refute leaf_id(view) == old
      assert leaf_content(view) == ""

      # A late message of the old document, and a Save: nothing is written.
      edit_body(view, "Eestikeelne muudatus", doc: old)
      assert save(view, %{}) =~ "No changes"

      refute File.exists?(Path.join([root, "order_offer", "markdown.en.md"]))
      refute File.exists?(Path.join([root, "order_offer", "text.en.txt"]))
      assert {:error, :enoent} = read(root, "markdown.et.md")
    end

    test "choosing another template asks first, too", %{tmp_dir: root} do
      seed(root)
      put(root, "order_other", "text.et.txt", "Teine")
      view = mount_editor(root)
      select(view, "order_offer")
      edit_body(view, "Unsaved")

      select(view, "order_other")
      assert has_element?(view, "#editor-confirm-switch")
      assert leaf_content(view) == "Tere!\n\n{{documents_list}}"
      refute has_element?(view, "#editor-title", "order_other")

      view |> element("#editor-confirm-switch-discard") |> render_click()

      assert has_element?(view, "#editor-title", "order_other")
      assert leaf_content(view) == "Teine"
    end

    test "the same template or language clicked again asks nothing", %{tmp_dir: root} do
      view = letter(root)
      edit_body(view, "Unsaved")

      select(view, "order_offer")
      tab(view, "et")

      refute has_element?(view, "#editor-confirm-switch")
      assert save(view, %{}) =~ "Saved"
    end

    test "with nothing unsaved a switch goes straight through", %{tmp_dir: root} do
      view = letter(root)

      tab(view, "ru")
      refute has_element?(view, "#editor-confirm-switch")
      assert has_element?(view, "#editor-languages [aria-pressed=true]", "Русский")
    end

    test "creating a template or opening a module email asks first, too", %{tmp_dir: root} do
      view = letter(root)
      edit_body(view, "Unsaved")

      create(view, "order_copy", "order_offer")
      assert has_element?(view, "#editor-confirm-switch")
      refute File.exists?(Path.join(root, "order_copy"))

      view |> element("#editor-confirm-switch-discard") |> render_click()
      assert File.dir?(Path.join(root, "order_copy"))
    end

    test "a discard with nothing waiting does nothing", %{tmp_dir: root} do
      view = letter(root)

      render_click(with_target(view, "#editor"), "confirm_switch", %{})
      assert has_element?(view, "#editor-languages [aria-pressed=true]", "Eesti")
    end

    test "a saved body is not unsaved: no question", %{tmp_dir: root} do
      view = letter(root)
      edit_body(view, "Saved soon")
      save(view, %{})

      tab(view, "ru")

      refute has_element?(view, "#editor-confirm-switch")
    end
  end

  describe "the variables" do
    test "a click sends the placeholder to the open Leaf, at its caret", %{tmp_dir: root} do
      view = letter(root)
      doc = leaf_id(view)

      view |> element("#editor-variables button[phx-value-name=order_number]") |> render_click()

      assert_push_event(view, "leaf-command:" <> ^doc, %{
        action: "insert_markdown",
        text: "{{order_number}}"
      })
    end

    test "the button keeps the focus where it was", %{tmp_dir: root} do
      view = letter(root)

      assert view
             |> element("#editor-variables button[phx-value-name=order_number]")
             |> render() =~ "onmousedown=\"event.preventDefault()\""
    end
  end

  describe "the preview and the text version" do
    test "a letter's preview is one view, the letter; the host's text is not a tab",
         %{tmp_dir: root} do
      view = letter(root, %{preview: {Host, :preview_with_text}})

      assert has_element?(view, "#editor-preview iframe")
      refute has_element?(view, "#editor-preview-tabs")
      refute has_element?(view, "#editor-preview-text")
    end

    test "the text version opens from the template's actions, read only", %{tmp_dir: root} do
      view = letter(root, %{preview: {Host, :preview_with_text}})

      refute has_element?(view, "#editor-text-version-modal[open]")
      view |> element("#editor-text-version") |> render_click()

      assert view |> element("#editor-text-version-text") |> render() =~
               "Hello from order_offer &lt;as text&gt;"

      refute has_element?(view, "#editor-text-version-modal textarea")
      refute has_element?(view, "#editor-text-version-modal input")

      view |> element("#editor-text-version-close") |> render_click()
      refute render(view) =~ ~r/id="editor-text-version-modal"[^>]*\sopen/
    end

    test "without a text from the host, the text file is shown", %{tmp_dir: root} do
      view = letter(root)

      view |> element("#editor-text-version") |> render_click()

      assert view |> element("#editor-text-version-text") |> render() =~ "{{documents_list}}"
    end

    test "a template that is not a letter has no such action, and its tabs stay",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{preview: {Host, :preview_with_text}})
      select(view, "_header-shop")

      refute has_element?(view, "#editor-text-version")
      assert has_element?(view, "#editor-preview-tabs")

      render_click(with_target(view, "#editor"), "text_version", %{})
      refute has_element?(view, "#editor-text-version-text")
    end
  end

  describe "a block placeholder and a nested list in the saved body" do
    test "no break beside the line of a block variable; the text still has the line",
         %{tmp_dir: root} do
      view = letter(root, %{block_placeholders: ["documents_list"]})

      edit_body(view, "Label:\n{{documents_list}}\n\nNext\nline")
      save(view, %{})

      assert read(root, "markdown.et.md") == {:ok, "Label:\n{{documents_list}}\n\nNext\\\nline"}
      assert read(root, "text.et.txt") == {:ok, "Label:\n{{documents_list}}\n\nNext\nline\n"}
    end

    test "without block variables every break is marked, as before", %{tmp_dir: root} do
      view = letter(root)

      edit_body(view, "Label:\n{{documents_list}}\n\nNext")
      save(view, %{})

      assert read(root, "markdown.et.md") == {:ok, "Label:\\\n{{documents_list}}\n\nNext"}
    end

    test "the same body saved again (opened from its file) writes the same files", %{
      tmp_dir: root
    } do
      view = letter(root, %{block_placeholders: ["documents_list"]})
      edit_body(view, "A\nB\n{{documents_list}}\nC")
      save(view, %{})
      {:ok, markdown} = read(root, "markdown.et.md")
      {:ok, text} = read(root, "text.et.txt")

      assert leaf_content(view) == "A\nB\n{{documents_list}}\nC"
      edit_body(view, "A\nB\n{{documents_list}}\nC", dirty: true)
      assert save(view, %{}) =~ "No changes"
      assert read(root, "markdown.et.md") == {:ok, markdown}
      assert read(root, "text.et.txt") == {:ok, text}
    end

    test "a nested list is written as Leaf has it, no backslash on a parent item",
         %{tmp_dir: root} do
      view = letter(root)

      edit_body(view, "- a\n  - b\n    - c\n- d\n\n1. x\n   1. y")
      save(view, %{})

      assert read(root, "markdown.et.md") == {:ok, "- a\n  - b\n    - c\n- d\n\n1. x\n   1. y"}
    end

    test "a blank-room letter: its text file stays byte for byte until the body is edited",
         %{tmp_dir: root} do
      seed(root)
      room = "Tere!\n\n\n\nLugupidamisega\n"
      put(root, "order_offer", "text.et.txt", room)
      view = mount_editor(root)
      select(view, "order_offer")

      assert save(view, %{subject: "Uus"}) =~ "Saved"
      assert read(root, "text.et.txt") == {:ok, room}
      assert {:error, :enoent} = read(root, "markdown.et.md")
    end

    test "a body over the limit is refused before anything is read into Markdown",
         %{tmp_dir: root} do
      view = letter(root)

      edit_body(view, String.duplicate(" ", Overrides.max_bytes() + 1))
      {microseconds, html} = :timer.tc(fn -> save(view, %{}) end)

      assert html =~ "Not saved: Body: larger than"
      assert microseconds < 2_000_000
      assert {:error, :enoent} = read(root, "markdown.et.md")
    end
  end

  describe "the order of the two writes" do
    test "the Markdown first; a text that is refused leaves the new canon and is tried again",
         %{tmp_dir: root} do
      too_big = String.duplicate("a", Overrides.max_bytes() + 1)
      view = letter(root, %{convert: %{to_text: fn _format, _source -> too_big end}})

      edit_body(view, "Uus")
      html = save(view, %{})

      assert html =~ "Saved: Markdown. Not saved: Text: larger than"
      assert read(root, "markdown.et.md") == {:ok, "Uus"}
      assert read(root, "text.et.txt") == {:ok, "Tere!\n\n{{documents_list}}\n"}

      # The body is still the writer's to save: the text is made again.
      send(view.pid, {:put, %{convert: %{to_text: fn _format, _source -> "Uus" end}}})
      _ = render(view)
      assert save(view, %{}) =~ "Saved"
      assert read(root, "text.et.txt") == {:ok, "Uus\n"}
    end

    test "a Markdown that is refused: the text made from it is not written beside the old one",
         %{tmp_dir: root} do
      view = letter(root, %{convert: %{to_text: fn _format, _source -> "short" end}})

      # As many bytes as a file may hold, until its line breaks are marked.
      edit_body(view, String.duplicate("a\n", div(Overrides.max_bytes(), 2)))
      html = save(view, %{subject: "Uus"})

      assert html =~ "Saved: Subject. Not saved: Markdown: larger than"
      assert read(root, "text.et.txt") == {:ok, "Tere!\n\n{{documents_list}}\n"}
      assert {:error, :enoent} = read(root, "markdown.et.md")
      assert read(root, "subject.et.txt") == {:ok, "Uus\n"}
    end
  end

  describe "Discard when the event that follows opens nothing else" do
    defp assert_redrawn(view, root) do
      assert leaf_content(view) == "Tere!\n\n{{documents_list}}"
      refute has_element?(view, "#editor-confirm-switch")
      assert save(view, %{}) =~ "No changes"
      assert read(root, "markdown.et.md") == {:error, :enoent}
    end

    test "a template made with a bad name: the form is drawn from the files again",
         %{tmp_dir: root} do
      view = letter(root)
      before = leaf_id(view)
      edit_body(view, "Typed")

      create(view, "Bad Name!")
      view |> element("#editor-confirm-switch-discard") |> render_click()

      refute leaf_id(view) == before
      assert_redrawn(view, root)
    end

    test "a template that is gone meanwhile", %{tmp_dir: root} do
      seed(root)
      put(root, "order_gone", "text.et.txt", "Teine")
      view = mount_editor(root)
      select(view, "order_offer")
      edit_body(view, "Typed")

      select(view, "order_gone")
      File.rm_rf!(Path.join(root, "order_gone"))
      send(view.pid, {:put, %{sample_variables: %{"order_number" => "1"}}})
      view |> element("#editor-confirm-switch-discard") |> render_click()

      refute has_element?(view, "#editor-confirm-switch")
      # Whichever document the form holds is the one Save writes: nothing is left unsaved.
      assert save(view, %{}) =~ "No changes"
    end

    test "an override the host refuses", %{tmp_dir: root} do
      view =
        letter(root, %{
          authorize: fn action -> if action == :save, do: :ok, else: {:error, :nope} end
        })

      edit_body(view, "Typed")
      target = with_target(view, "#editor")

      render_click(target, "override_default", %{"name" => "billing_invoice"})
      assert has_element?(view, "#editor-confirm-switch")

      view |> element("#editor-confirm-switch-discard") |> render_click()

      assert_redrawn(view, root)
    end
  end

  describe "Reload with something unsaved" do
    test "asks first; Stay keeps the body, Discard reads the files again", %{tmp_dir: root} do
      view = letter(root)
      edit_body(view, "Typed")

      render_click(with_target(view, "#editor"), "reload", %{})

      assert has_element?(view, "#editor-confirm-switch")
      view |> element("#editor-confirm-switch-cancel") |> render_click()
      assert save(view, %{}) =~ "Saved"
      assert read(root, "markdown.et.md") == {:ok, "Typed"}

      edit_body(view, "Other")
      render_click(with_target(view, "#editor"), "reload", %{})
      view |> element("#editor-confirm-switch-discard") |> render_click()

      assert leaf_content(view) == "Typed"
      assert save(view, %{}) =~ "No changes"
    end

    test "from the conflict panel too, whose sentence stays true", %{tmp_dir: root} do
      view = letter(root)
      edit_body(view, "Typed")
      File.write!(Path.join([root, "order_offer", "text.et.txt"]), "Teise käe all\n")
      Overrides.reset_cache([root])
      send(view.pid, {:put, %{sample_variables: %{"order_number" => "2"}}})
      _ = render(view)

      assert save(view, %{}) =~ "changed on disk"
      view |> element("#editor-conflict-reload") |> render_click()

      assert has_element?(view, "#editor-confirm-switch")
      view |> element("#editor-confirm-switch-cancel") |> render_click()
      assert has_element?(view, "#editor-conflict")
    end

    test "with nothing unsaved it reloads at once", %{tmp_dir: root} do
      view = letter(root)
      render_click(with_target(view, "#editor"), "reload", %{})
      refute has_element?(view, "#editor-confirm-switch")
    end
  end

  describe "an unsaved label or subject" do
    defp type(view, parts) do
      view |> form("#editor-parts", parts: parts) |> render_change()
    end

    test "a switch asks first, like an unsaved body", %{tmp_dir: root} do
      view = letter(root)

      type(view, %{subject: "Muudetud teema"})
      tab(view, "ru")

      assert has_element?(view, "#editor-confirm-switch")
      view |> element("#editor-confirm-switch-cancel") |> render_click()
      assert has_element?(view, "#editor-languages [aria-pressed=true]", "Eesti")

      assert save(view, %{subject: "Muudetud teema"}) =~ "Saved"
      tab(view, "ru")
      refute has_element?(view, "#editor-confirm-switch")
    end

    test "typed and put back as it was, it asks nothing", %{tmp_dir: root} do
      view = letter(root)

      type(view, %{label: "Muudetud"})
      type(view, %{label: "Pakkumiskiri"})
      tab(view, "ru")

      refute has_element?(view, "#editor-confirm-switch")
    end

    test "Discard drops it and switches", %{tmp_dir: root} do
      view = letter(root)

      type(view, %{label: "Muudetud"})
      select(view, "_header-shop")
      view |> element("#editor-confirm-switch-discard") |> render_click()

      assert has_element?(view, "#editor-title", "_header-shop")
      select(view, "order_offer")
      refute has_element?(view, "#editor-confirm-switch")
      assert field(view, :label) == "Pakkumiskiri"
    end

    test "a forged or malformed change event is harmless", %{tmp_dir: root} do
      view = letter(root)
      target = with_target(view, "#editor")

      render_click(target, "form_changed", %{})
      render_click(target, "form_changed", %{"parts" => "x"})
      render_click(target, "form_changed", %{"parts" => %{"subject" => 42}})

      tab(view, "ru")
      refute has_element?(view, "#editor-confirm-switch")
    end
  end

  describe "the form is drawn again when the server holds it as clean" do
    defp form_rev(view) do
      view
      |> element("#editor-part-subject")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-form-rev]")
      |> Enum.flat_map(&LazyHTML.attribute(&1, "data-form-rev"))
    end

    test "Discard that stays on the letter bumps the revision of every field", %{tmp_dir: root} do
      view = letter(root)
      before = form_rev(view)
      type(view, %{subject: "Typed"})

      render_click(with_target(view, "#editor"), "reload", %{})
      view |> element("#editor-confirm-switch-discard") |> render_click()

      refute form_rev(view) == before
      assert field(view, :subject) == "Pakkumine {{order_number}}"
    end

    test "so does a save", %{tmp_dir: root} do
      view = letter(root)
      before = form_rev(view)

      save(view, %{subject: "Uus"})

      refute form_rev(view) == before
    end
  end

  describe "what a parent re-render does to a typed body" do
    test "nothing: the body is still there to be saved", %{tmp_dir: root} do
      view = letter(root)
      doc = leaf_id(view)
      edit_body(view, "Typed")

      send(view.pid, {:put, %{sample_variables: %{"order_number" => "99"}}})
      _ = render(view)

      assert leaf_id(view) == doc
      assert save(view, %{}) =~ "Saved"
      assert read(root, "markdown.et.md") == {:ok, "Typed"}
    end
  end

  describe "the label and subject the browser sends without the file's final newline" do
    test "are not a change: no question", %{tmp_dir: root} do
      view = letter(root)

      type(view, %{subject: "Pakkumine {{order_number}}", label: "Pakkumiskiri"})
      tab(view, "ru")

      refute has_element?(view, "#editor-confirm-switch")
    end

    test "a wrapped subject shown joined with spaces, sent as shown, is not a change either",
         %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "subject.et.txt", "First line\nsecond line\n")
      view = mount_editor(root)
      select(view, "order_offer")

      type(view, %{subject: "First line second line"})
      tab(view, "ru")

      refute has_element?(view, "#editor-confirm-switch")
    end
  end

  describe "a line break typed in the two-row label or subject" do
    test "at the end is not a change: no question, nothing written", %{tmp_dir: root} do
      view = letter(root)

      type(view, %{subject: "Pakkumine {{order_number}}\n"})
      tab(view, "ru")

      refute has_element?(view, "#editor-confirm-switch")
    end

    test "at the end of an edited subject is dropped: the file keeps its one line",
         %{tmp_dir: root} do
      view = letter(root)

      assert save(view, %{subject: "Uus pakkumine\n\n"}) =~ "Saved"
      assert read(root, "subject.et.txt") == {:ok, "Uus pakkumine\n"}
    end
  end

  describe "the toolbar" do
    test "is Leaf's compact one: no headings, tables, callouts or code blocks",
         %{tmp_dir: root} do
      view = letter(root)
      html = view |> element("#editor-body") |> render() |> LazyHTML.from_fragment()

      presets =
        html
        |> LazyHTML.query("[data-toolbar-preset]")
        |> Enum.flat_map(&LazyHTML.attribute(&1, "data-toolbar-preset"))
        |> Enum.uniq()

      assert presets == ["simple"]

      actions =
        html
        |> LazyHTML.query("button[data-toolbar-action]")
        |> Enum.flat_map(&LazyHTML.attribute(&1, "data-toolbar-action"))
        |> Enum.sort()

      # Leaf's phone toolbar keeps one «Heading» in its «More formatting» menu
      # whatever the preset; nothing else a letter cannot carry is there.
      assert Enum.uniq(actions) ==
               ~w(bold bulletList code emoji heading2 italic link orderedList redo removeFormat strike undo)

      refute has_element?(view, "#editor-body [data-heading-dropdown]")
      refute has_element?(view, "#editor-body [data-table-dropdown]")
    end
  end

  defp send_leaf(view, message) do
    Phoenix.LiveView.send_update(view.pid, PhoenixKitTemplatesEditor.Web.Editor,
      id: "editor",
      leaf: message
    )

    render(view)
  end

  defp send_mode(view, mode),
    do: send_leaf(view, {:leaf_mode_changed, %{editor_id: leaf_id(view), mode: mode}})
end
