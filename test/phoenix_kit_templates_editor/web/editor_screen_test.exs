defmodule PhoenixKitTemplatesEditor.Web.EditorScreenTest do
  # The editor's screen: the list that never spills into the template's
  # pane, the phone showing the list first and a template second, the
  # language switcher (the module's languages, "Default" last), the
  # confirmations in modals, the collapsible sections. What a browser would
  # check — an overflow, a width — is not here; the markup that prevents it is.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  defp classes(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("class")
    |> List.first()
    |> String.split()
  end

  defp lg_hidden?(view, selector) do
    classes = classes(view, selector)
    "hidden" in classes and "lg:flex" in classes
  end

  describe "the list" do
    test "an entry: the label first, the key under it in mono, the badge on its own line",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{locale: "et"})

      entry = "#editor-messages [phx-click=select][phx-value-name=order_offer]"

      assert [label, key] =
               view
               |> element(entry)
               |> render()
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("button > span")
               |> Enum.map(&LazyHTML.text/1)
               |> Enum.map(&String.trim/1)

      assert label == "Pakkumiskiri"
      assert key == "order_offer"
      assert "font-mono" in classes(view, entry <> " > span:nth-child(2)")
      assert "break-all" in classes(view, entry <> " > span:nth-child(2)")
    end

    test "a module email: the badge is a line of its own, after the key", %{tmp_dir: root} do
      seed(root)

      view =
        mount_editor(root, %{
          module_emails: [%{name: "billing_invoice", label: "Invoice", sample_variables: %{}}]
        })

      entry = "#editor-module-emails [phx-value-name=billing_invoice]"

      spans =
        view
        |> element(entry)
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("button > span")

      assert Enum.count(spans) == 3
      assert spans |> Enum.at(2) |> LazyHTML.text() =~ "built-in text"
      assert "break-all" in classes(view, entry <> " > span:nth-child(2)")
    end

    test "the columns and the lists may shrink below their content", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)

      assert "min-w-0" in classes(view, "#editor-list")
      assert "min-w-0" in classes(view, "#editor-detail")
      assert "min-w-0" in classes(view, "#editor-panes")
      assert "flex-nowrap" in classes(view, "#editor-messages ul")
      assert "min-w-0" in classes(view, "#editor-messages li")
    end
  end

  describe "a phone: the list first, the template second" do
    test "opens on the list; the template's pane waits behind it, shown from lg up",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)

      refute lg_hidden?(view, "#editor-list")
      assert lg_hidden?(view, "#editor-detail")
    end

    # An empty pane beside the list reads as a failure on a wide screen.
    test "the first message is open from the start, behind the list", %{tmp_dir: root} do
      seed(root)
      put(root, "order_zebra", "text.et.txt", "Zebra\n")
      view = mount_editor(root)

      assert has_element?(view, "#editor-list .menu-active[phx-value-name=order_offer]")
      assert has_element?(view, "#editor-parts")
      assert has_element?(view, "#editor-preview")
      refute lg_hidden?(view, "#editor-list")
    end

    test "the template the page's address names opens instead, on its own screen",
         %{tmp_dir: root} do
      seed(root)
      put(root, "order_zebra", "text.et.txt", "Zebra\n")
      view = mount_editor(root, %{open: "order_zebra"})

      assert has_element?(view, "#editor-list .menu-active[phx-value-name=order_zebra]")
      assert lg_hidden?(view, "#editor-list")
      refute lg_hidden?(view, "#editor-detail")
    end

    test "a name the address gives that is not a template here: the first message",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{open: "secret_other"})

      assert has_element?(view, "#editor-list .menu-active[phx-value-name=order_offer]")
      refute lg_hidden?(view, "#editor-list")
    end

    test "choosing a template shows its screen, the list gives way, with a back control",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      assert lg_hidden?(view, "#editor-list")
      refute lg_hidden?(view, "#editor-detail")
      assert has_element?(view, "#editor-back")
      assert "lg:hidden" in classes(view, "#editor-back")
    end

    test "back returns to the list; the template stays open behind it, form and all",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      view |> element("#editor-back") |> render_click()

      refute lg_hidden?(view, "#editor-list")
      assert lg_hidden?(view, "#editor-detail")
      assert has_element?(view, "#editor-parts")

      select(view, "order_offer")
      refute lg_hidden?(view, "#editor-detail")
    end

    test "a module email opens on the detail pane too", %{tmp_dir: root} do
      seed(root)

      view =
        mount_editor(root, %{
          module_emails: [%{name: "billing_invoice", label: "Invoice", sample_variables: %{}}]
        })

      view
      |> element("#editor-module-emails [phx-click=select_module]")
      |> render_click()

      assert lg_hidden?(view, "#editor-list")
      refute lg_hidden?(view, "#editor-detail")
    end

    test "a template deleted: back on the list", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      view |> element("#editor-delete") |> render_click()
      view |> element("#editor-delete-confirm") |> render_click()

      refute lg_hidden?(view, "#editor-list")
      assert lg_hidden?(view, "#editor-detail")
    end
  end

  describe "the language switcher" do
    test "the module's languages by name, the files without a language last as Default",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      assert [
               {["et"], "🇪🇪 Eesti"},
               {["ru"], "🇷🇺 Русский"},
               {["en"], "🇺🇸 English"},
               {[""], "Default"}
             ] =
               view
               |> element("#editor-languages")
               |> render()
               |> LazyHTML.from_fragment()
               |> LazyHTML.query("[role=tab]")
               |> Enum.map(fn button ->
                 {LazyHTML.attribute(button, "phx-value-language"),
                  button |> LazyHTML.text() |> String.split() |> Enum.join(" ")}
               end)
    end

    test "the open language is the pressed one; a click switches and loads its files",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      assert has_element?(view, "#editor-languages [aria-pressed=true]", "Eesti")

      tab(view, "ru")

      assert has_element?(view, "#editor-languages [aria-pressed=true]", "Русский")
      assert field(view, :subject) == "Предложение"
    end

    test "Default switches to the files without a language", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "subject.txt", "Fallback subject\n")
      view = mount_editor(root)
      select(view, "order_offer")

      tab(view, "")

      assert has_element?(view, "#editor-languages [aria-pressed=true]", "Default")
      assert field(view, :subject) == "Fallback subject"
    end

    test "a language the template does not have is no switch", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{email_fallback: false})
      select(view, "order_offer")

      render_click(with_target(view, "#editor"), "locale", %{"language" => ""})
      render_click(with_target(view, "#editor"), "locale", %{"language" => "de"})

      assert has_element?(view, "#editor-languages [aria-pressed=true]", "Eesti")
    end

    test "the module email view has the same switcher, without Default", %{tmp_dir: root} do
      seed(root)

      view =
        mount_editor(root, %{
          module_emails: [%{name: "billing_invoice", label: "Invoice", sample_variables: %{}}]
        })

      view |> element("#editor-module-emails [phx-click=select_module]") |> render_click()

      assert has_element?(view, "#editor-module-languages [aria-pressed=true]", "Eesti")
      refute has_element?(view, "#editor-module-languages [phx-value-language='']")

      view
      |> element("#editor-module-languages [phx-click=module_locale][phx-value-language=ru]")
      |> render_click()

      assert has_element?(view, "#editor-module-languages [aria-pressed=true]", "Русский")
    end

    test "with the page in Estonian the entry is named Vaikimisi", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{locale: "et"})
      select(view, "order_offer")

      assert has_element?(view, "#editor-languages [phx-value-language='']", "Vaikimisi")
    end
  end

  describe "confirmations are modals" do
    test "deleting a template: the modal appears on Delete, the template goes on Delete there",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      refute has_element?(view, "#editor-delete-modal")
      view |> element("#editor-delete") |> render_click()
      assert has_element?(view, "dialog#editor-delete-modal #editor-delete-confirm")

      view |> element("#editor-delete-cancel") |> render_click()
      refute has_element?(view, "#editor-delete-modal")
      assert File.exists?(Path.join(root, "order_offer"))
    end

    test "deleting a layout", %{tmp_dir: root} do
      seed(root)
      put(root, "_header-shop-x", "html.html", "<p>X</p>")

      view = mount_editor(root, %{layout_groups: ["shop"], layout_group: "shop"})

      view |> element("#editor-layout-shop-x_delete") |> render_click()
      assert has_element?(view, "dialog#editor-layouts-delete #editor-layouts-delete-confirm")

      view |> element("#editor-layouts-delete-cancel") |> render_click()
      refute has_element?(view, "#editor-layouts-delete")
    end

    test "Save anyway", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      edit_body(view, "Hello {{site_name}}")
      save(view, %{})

      assert has_element?(view, "dialog#editor-confirm-variables #editor-confirm-variables-save")

      view |> element("#editor-confirm-variables-cancel") |> render_click()
      refute has_element?(view, "#editor-confirm-variables")
    end
  end

  describe "the template's heading" do
    test "its label, with the key under it in small mono type", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{locale: "et"})
      select(view, "order_offer")

      assert has_element?(view, "#editor-title", "Pakkumiskiri")
      refute has_element?(view, "#editor-title", "order_offer")
      assert has_element?(view, "#editor-key", "order_offer")
      assert "break-all" in classes(view, "#editor-key")
      assert "font-mono" in classes(view, "#editor-key")
    end

    test "without a label the key is the heading, and appears once", %{tmp_dir: root} do
      seed(root)
      for file <- Path.wildcard(Path.join([root, "order_offer", "label.*"])), do: File.rm!(file)
      view = mount_editor(root)
      select(view, "order_offer")

      assert has_element?(view, "#editor-title", "order_offer")
      refute has_element?(view, "#editor-key")
    end
  end

  describe "the label shown for a template (list and heading)" do
    defp caption_of(view, name),
      do:
        view
        |> element("#editor-messages [phx-value-name=#{name}] > span:first-child")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.text()
        |> String.trim()

    setup %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "label.ru.txt", "Коммерческое предложение\n")
      :ok
    end

    test "the page's language first, when the template has a label in it", %{tmp_dir: root} do
      view = mount_editor(root, %{locale: "ru"})
      assert caption_of(view, "order_offer") == "Коммерческое предложение"

      select(view, "order_offer")
      assert has_element?(view, "#editor-title", "Коммерческое предложение")
    end

    test "the page's regional locale counts by its base code", %{tmp_dir: root} do
      view = mount_editor(root, %{locale: "ru_RU"})
      assert caption_of(view, "order_offer") == "Коммерческое предложение"
    end

    test "no label in the page's language: the module's languages in their order",
         %{tmp_dir: root} do
      File.rm!(Path.join([root, "order_offer", "label.ru.txt"]))

      view = mount_editor(root, %{locale: "ru"})
      assert caption_of(view, "order_offer") == "Pakkumiskiri"

      view = mount_editor(root, %{locale: "ru", locales: ["en", "et", "ru"]})
      assert caption_of(view, "order_offer") == "Price offer"
    end

    test "an empty label in the page's language is passed over", %{tmp_dir: root} do
      put(root, "order_offer", "label.ru.txt", "  \n")

      view = mount_editor(root, %{locale: "ru"})
      assert caption_of(view, "order_offer") == "Pakkumiskiri"
    end

    test "no label anywhere: the key", %{tmp_dir: root} do
      for file <- Path.wildcard(Path.join([root, "order_offer", "label.*"])), do: File.rm!(file)

      view = mount_editor(root, %{locale: "ru"})
      assert caption_of(view, "order_offer") == "order_offer"

      select(view, "order_offer")
      assert has_element?(view, "#editor-title", "order_offer")
      refute has_element?(view, "#editor-key")
    end
  end

  describe "the template's header on a phone" do
    test "the title and the buttons are a column below sm, a row from sm", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      classes = classes(view, "#editor-header")
      assert "flex-col" in classes
      assert "sm:flex-row" in classes
      assert has_element?(view, "#editor-header #editor-delete")
    end
  end

  describe "one-line fields" do
    test "the label and the subject are single-line inputs; a letter's body is Leaf, a header's parts textareas",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      for part <- ~w(label subject) do
        assert has_element?(view, "#editor-parts input[type=text][name='parts[#{part}]']")
        refute has_element?(view, "#editor-parts textarea[name='parts[#{part}]']")
      end

      for part <- ~w(text markdown html) do
        refute has_element?(view, "#editor-parts [name='parts[#{part}]']")
      end

      select(view, "_header-shop")
      tab(view, "")

      for part <- ~w(text markdown html) do
        assert has_element?(view, "#editor-parts textarea[name='parts[#{part}]']")
      end
    end

    test "a save that touches only the body leaves the files' own trailing newlines alone",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      edit_body(view, "New body")
      assert save(view, %{}) =~ "Saved."

      assert File.read!(Path.join([root, "order_offer", "subject.et.txt"])) ==
               "Pakkumine {{order_number}}\n"

      assert File.read!(Path.join([root, "order_offer", "label.et.txt"])) == "Pakkumiskiri\n"
    end

    test "an edited subject or label keeps the trailing newline its file had", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      assert save(view, %{subject: "New subject", label: "New label"}) =~ "Saved."

      assert File.read!(Path.join([root, "order_offer", "subject.et.txt"])) == "New subject\n"
      assert File.read!(Path.join([root, "order_offer", "label.et.txt"])) == "New label\n"
    end

    test "a file that had no trailing newline gets none", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "subject.et.txt", "Bare subject")
      view = mount_editor(root)
      select(view, "order_offer")

      assert save(view, %{subject: "Other subject"}) =~ "Saved."

      assert File.read!(Path.join([root, "order_offer", "subject.et.txt"])) == "Other subject"
    end

    test "a new subject file (none before) is written as typed", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")
      tab(view, "en")

      assert save(view, %{subject: "English subject"}) =~ "Saved."

      assert File.read!(Path.join([root, "order_offer", "subject.en.txt"])) == "English subject"
    end

    test "a wrapped subject on disk is shown joined with spaces and not rewritten by a body save",
         %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "subject.et.txt", "First line\nsecond line\n")
      view = mount_editor(root)
      select(view, "order_offer")

      assert field(view, :subject) == "First line second line"

      edit_body(view, "New body")
      assert save(view, %{}) =~ "Saved."

      assert File.read!(Path.join([root, "order_offer", "subject.et.txt"])) ==
               "First line\nsecond line\n"
    end

    test "a wrapped subject that is edited is saved as the one line the user sees, newline kept",
         %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "subject.et.txt", "First line\nsecond line\n")
      view = mount_editor(root)
      select(view, "order_offer")

      assert save(view, %{subject: "First line second line!"}) =~ "Saved."

      assert File.read!(Path.join([root, "order_offer", "subject.et.txt"])) ==
               "First line second line!\n"
    end

    test "emptying a one-line field deletes its file, as before", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      assert save(view, %{label: ""}) =~ "Saved."

      refute File.exists?(Path.join([root, "order_offer", "label.et.txt"]))
    end

    test "a subject that arrives with a line break is still refused", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      html = save(view, %{subject: "First\nSecond"})

      assert html =~ "one line"

      assert File.read!(Path.join([root, "order_offer", "subject.et.txt"])) ==
               "Pakkumine {{order_number}}\n"
    end
  end

  describe "the Reload action" do
    test "the list has its own button unless the host puts it elsewhere", %{tmp_dir: root} do
      seed(root)
      assert has_element?(mount_editor(root), "#editor-list #editor-reload")

      view = mount_editor(root, %{show_reload: false})
      refute has_element?(view, "#editor-reload")
    end
  end

  describe "sections" do
    test "the variables and the preview are collapsible sections", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      assert has_element?(view, "details#editor-variables summary", "Variables")
      assert has_element?(view, "details#editor-preview[open] summary", "Preview")
      refute has_element?(view, "details#editor-variables[open]")
      assert has_element?(view, "#editor-variables-order_number")
    end

    test "no hint paragraphs under the fields or in the lists", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      html = select(view, "order_offer")

      refute html =~ "The plain-text body"
      refute html =~ "Click a variable to put it"
      refute html =~ "Sent by PhoenixKit and its modules"
    end
  end
end
