defmodule PhoenixKitTemplatesEditor.Web.EditorHardeningTest do
  # Hardening of the editor: a host's preview and "Send
  # to me" never get a template with a link in it and the preview is
  # bounded; a copy refuses a source with a link, a save a template
  # directory that is a link; the preview frame carries its policy inside
  # the document too; "Reload" is a change; the root's limits.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  defp counting_preview(test_pid) do
    fn name, locale ->
      send(test_pid, {:previewed, name})
      Host.preview(name, locale)
    end
  end

  defp srcdoc(view) do
    view
    |> element("#editor-preview iframe")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("srcdoc")
    |> List.first()
  end

  describe "a host's preview" do
    test "is not asked for a template with a link in it", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "notes.txt", "INSIDE")
      File.ln_s!("notes.txt", Path.join([root, "order_offer", "html.et.html"]))

      view = mount_editor(root, %{preview: counting_preview(self())})
      html = select(view, "order_offer")

      refute_received {:previewed, "order_offer"}
      assert view |> element("#editor-preview") |> render() =~ "order_offer/html.et.html"
      refute html =~ "INSIDE"
    end

    test "is not asked when the email's layout has a link", %{tmp_dir: root} do
      seed(root)
      put(root, "_footer-shop", "notes.txt", "INSIDE")
      File.ln_s!("notes.txt", Path.join([root, "_footer-shop", "html.html"]))

      view = mount_editor(root, %{layout_group: "shop", preview: counting_preview(self())})
      select(view, "order_offer")

      refute_received {:previewed, "order_offer"}
      assert view |> element("#editor-preview") |> render() =~ "_footer-shop/html.html"
    end

    test "past its deadline is an error, not a stuck page", %{tmp_dir: root} do
      seed(root)

      view =
        mount_editor(root, %{
          preview_timeout: 50,
          preview: fn _name, _locale -> Process.sleep(:infinity) end
        })

      select(view, "order_offer")

      assert view |> element("#editor-preview") |> render() =~ "it took too long"
    end
  end

  describe "the preview frame" do
    test "carries its policy in the document as well as on the frame", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      assert srcdoc(view) =~
               ~r{\A<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">}
    end

    test "after a document's doctype, so it keeps its rendering mode", %{tmp_dir: root} do
      seed(root)

      view =
        mount_editor(root, %{
          preview: fn _name, _locale ->
            {"S", "<!DOCTYPE html>\n<html><head></head><body><p>Hi</p></body></html>"}
          end
        })

      select(view, "order_offer")

      assert srcdoc(view) =~
               ~r{\A<!DOCTYPE html><meta http-equiv="Content-Security-Policy" content="[^"]+">\n<html>}
    end
  end

  describe "Send to me" do
    test "is not asked for a template with a link in it", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "notes.txt", "INSIDE")
      File.ln_s!("notes.txt", Path.join([root, "order_offer", "markdown.et.md"]))
      test_pid = self()

      view =
        mount_editor(root, %{
          test_send: fn name, _locale ->
            send(test_pid, {:test_send, name})
            {:ok, "me@example.com"}
          end
        })

      select(view, "order_offer")
      html = view |> element("#editor-test-send") |> render_click()

      refute_received {:test_send, _name}
      assert html =~ "Not sent"
      assert html =~ "order_offer/markdown.et.md"
    end
  end

  describe "writing" do
    test "a copy of a template with a link in it is refused", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "notes.txt", "INSIDE")
      File.ln_s!("notes.txt", Path.join([root, "order_offer", "html.et.html"]))

      html = create(render_ready(mount_editor(root)), "order_copy", "order_offer")

      assert html =~ "Not copied"
      assert html =~ "order_offer/html.et.html"
      refute File.exists?(Path.join(root, "order_copy"))
    end

    test "a save into a template directory that is a link is refused", %{tmp_dir: root} do
      seed(root)
      File.ln_s!("order_offer", Path.join(root, "order_alias"))
      before = File.read!(Path.join([root, "order_offer", "subject.et.txt"]))

      view = mount_editor(root)
      select(view, "order_alias")
      html = save(view, %{subject: "Through the link"})

      assert html =~ "Not saved"
      assert File.read!(Path.join([root, "order_offer", "subject.et.txt"])) == before
    end
  end

  describe "Reload" do
    test "not offered read only, and refused there when sent anyway", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{editable: false})
      refute has_element?(view, "#editor-reload")

      put(root, "order_new", "subject.et.txt", "Uus")
      html = render_click(with_target(view, "#editor"), "reload", %{})

      assert html =~ "read-only"
      refute has_element?(view, "#editor [phx-click=select][phx-value-name=order_new]")
    end

    test "asks the host's authorize", %{tmp_dir: root} do
      seed(root)
      test_pid = self()

      view =
        mount_editor(root, %{
          authorize: fn action ->
            send(test_pid, {:authorize, action})
            {:error, :forbidden}
          end
        })

      html = view |> element("#editor-reload") |> render_click()

      assert_received {:authorize, :reload}
      assert html =~ "not allowed"
    end

    test "once in a few seconds", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)

      assert view |> element("#editor-reload") |> render_click() =~ "Read again from disk."

      put(root, "order_new", "subject.et.txt", "Uus")
      html = view |> element("#editor-reload") |> render_click()

      assert html =~ "wait"
      refute has_element?(view, "#editor [phx-click=select][phx-value-name=order_new]")
    end
  end

  describe "the root's limits" do
    test "no new template past max_templates", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{max_templates: 3})

      create(view, "order_new")
      html = save(view, %{subject: "Uus"})

      assert html =~ "3 templates"
      refute File.exists?(Path.join(root, "order_new"))

      html = create(view, "order_copy", "order_offer")
      assert html =~ "3 templates"
      refute File.exists?(Path.join(root, "order_copy"))
    end

    test "no save past max_root_bytes", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{max_root_bytes: 200})
      select(view, "order_offer")

      html = save(view, %{text: String.duplicate("a", 300)})

      assert html =~ "Not saved"
      assert html =~ "KiB"
      refute File.read!(Path.join([root, "order_offer", "text.et.txt"])) =~ "aaa"
    end
  end

  defp render_ready(view) do
    _ = render(view)
    view
  end
end
