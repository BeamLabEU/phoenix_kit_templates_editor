defmodule PhoenixKitTemplatesEditor.Web.EditorIncompleteTest do
  # An email (no leading "_") that is not complete in the base language is
  # flagged in the list: a host's send window leaves it out.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  @hint "Not offered for sending: no subject or body in"

  defp flagged?(view, name), do: has_element?(view, "#editor-messages-incomplete-#{name}")

  describe "the default rule: a subject and a body part in the base language" do
    test "flags an email without them, and nothing else", %{tmp_dir: root} do
      seed(root)
      # Subject but no body in et.
      put(root, "order_no_body", "subject.et.txt", "Teema")
      # Body but no subject in et.
      put(root, "order_no_subject", "html.et.html", "<p>Tere</p>")
      # Only in another language.
      put(root, "order_russian", "subject.ru.txt", "Тема")
      put(root, "order_russian", "text.ru.txt", "Текст")
      # Only locale-less files: the fallback does not count.
      put(root, "order_fallback", "subject.txt", "Subject")
      put(root, "order_fallback", "text.txt", "Text")
      # A blank body file is no body.
      put(root, "order_blank", "subject.et.txt", "Teema")
      put(root, "order_blank", "markdown.et.md", "  \n")
      # Complete with Markdown as its body.
      put(root, "order_markdown", "subject.et.txt", "Teema")
      put(root, "order_markdown", "markdown.et.md", "**Tere**")
      # A header has no subject of its own: never flagged.
      put(root, "_footer-shop", "html.et.html", "<p>Footer</p>")

      view = mount_editor(root)

      for name <- ~w(order_no_body order_no_subject order_russian order_fallback order_blank) do
        assert flagged?(view, name), "expected #{name} to be flagged"
      end

      refute flagged?(view, "order_offer")
      refute flagged?(view, "order_markdown")
      refute has_element?(view, "#editor-layouts [id*=incomplete]")

      assert view |> element("#editor-messages-incomplete-order_russian") |> render() =~
               "#{@hint} et"
    end

    test "the flag goes once the email is completed", %{tmp_dir: root} do
      seed(root)
      put(root, "order_new", "subject.et.txt", "Teema")
      view = mount_editor(root)
      assert flagged?(view, "order_new")

      select(view, "order_new")
      save(view, %{text: "Tere"})

      refute flagged?(view, "order_new")
    end

    test "the base language is base_locale, else the first locale", %{tmp_dir: root} do
      seed(root)

      view = mount_editor(root, %{base_locale: "ru"})
      assert flagged?(view, "order_offer")
      assert view |> element("#editor-messages-incomplete-order_offer") |> render() =~ "ru"

      view = mount_editor(root, %{locales: ["en", "et"]})
      assert flagged?(view, "order_offer")

      view = mount_editor(root, %{base_locale: "", locales: ["et", "en"]})
      refute flagged?(view, "order_offer")
    end

    test "no languages, no flag", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{locales: []})

      refute has_element?(view, "#editor [id*=incomplete]")
    end
  end

  describe "a host's complete? callback" do
    test "decides, asked with the name and the base language", %{tmp_dir: root} do
      seed(root)
      put(root, "order_other", "text.ru.txt", "Текст")
      test_pid = self()

      complete? = fn name, locale ->
        send(test_pid, {:complete?, name, locale})
        name == "order_other"
      end

      view = mount_editor(root, %{complete?: complete?})

      assert flagged?(view, "order_offer")
      refute flagged?(view, "order_other")
      assert_received {:complete?, "order_offer", "et"}
      assert_received {:complete?, "order_other", "et"}
      refute_received {:complete?, "_header-shop", _locale}
    end

    test "{module, function} is called like a function", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{complete?: {__MODULE__.Rule, :complete?}})

      assert flagged?(view, "order_offer")
    end

    test "one that fails or answers no boolean flags nothing", %{tmp_dir: root} do
      seed(root)
      put(root, "order_new", "subject.et.txt", "Teema")

      log =
        capture_log(fn ->
          view = mount_editor(root, %{complete?: fn _name, _locale -> raise "rule down" end})
          refute flagged?(view, "order_new")
        end)

      assert log =~ "complete?"
      assert log =~ "rule down"

      view = mount_editor(root, %{complete?: fn _name, _locale -> :maybe end})
      refute flagged?(view, "order_new")
    end
  end

  defmodule Rule do
    @moduledoc false
    def complete?(_name, _locale), do: false
  end
end
