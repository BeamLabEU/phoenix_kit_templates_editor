defmodule PhoenixKitTemplatesEditor.Web.EditorSafetyTest do
  # What the editor reads and shows (spec §4.10 Б4, Б7, Б10, Б13, §4.9 Н3):
  # a part file that is a link, or leads out of the root, or is larger than
  # a template file may be, is never read — the part is shown unavailable;
  # the preview's iframe loads nothing from outside; the module's converter
  # limits and an after_write warning are told in words.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  defp link!(root, name, file, target) do
    File.mkdir_p!(Path.join(root, name))
    File.ln_s!(target, Path.join([root, name, file]))
  end

  defp outside!(root, content) do
    path = Path.join(Path.dirname(root), "outside-#{System.unique_integer([:positive])}.txt")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  describe "a part that is a link or leads out of the root" do
    test "one leading out of the root is not read: its content and placeholders nowhere",
         %{tmp_dir: root} do
      seed(root)
      link!(root, "order_offer", "html.et.html", outside!(root, "SECRET-CONTENT {{secret_var}}"))

      view = mount_editor(root)
      html = select(view, "order_offer")

      refute html =~ "SECRET-CONTENT"
      refute html =~ "secret_var"
      refute html =~ Path.dirname(root)
    end

    test "a link to a file inside the root is shown unavailable, not read", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "notes.txt", "INSIDE-CONTENT {{inside_var}}")
      link!(root, "order_offer", "html.et.html", "notes.txt")

      view = mount_editor(root)
      html = select(view, "order_offer")

      assert has_element?(view, "#editor-part-html-invalid")
      assert html =~ "a link or outside the template directory"
      refute html =~ "INSIDE-CONTENT"
      refute html =~ "inside_var"
      refute html =~ root
    end

    test "is never written over, and stays as it was", %{tmp_dir: root} do
      seed(root)
      secret = outside!(root, "SECRET")
      link!(root, "order_offer", "html.et.html", secret)

      view = mount_editor(root)
      select(view, "order_offer")
      save(view, %{subject: "Uus"})

      assert File.read!(secret) == "SECRET"

      assert {:ok, %File.Stat{type: :symlink}} =
               File.lstat(Path.join([root, "order_offer", "html.et.html"]))
    end

    test "a linked label is no caption, a linked subject makes no email complete",
         %{tmp_dir: root} do
      put(root, "order_x", "text.et.txt", "Body")
      put(root, "order_x", "notes.txt", "SECRET-LABEL")
      link!(root, "order_x", "label.et.txt", "notes.txt")
      link!(root, "order_x", "subject.et.txt", "notes.txt")

      view = mount_editor(root)
      html = render(view)

      refute html =~ "SECRET-LABEL"
      assert has_element?(view, "#editor-messages-incomplete-order_x")
    end

    test "the read-only view shows it unavailable too", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "notes.txt", "INSIDE-CONTENT")
      link!(root, "order_offer", "html.et.html", "notes.txt")

      view = mount_editor(root, %{editable: false})
      html = select(view, "order_offer")

      refute html =~ "INSIDE-CONTENT"
      assert html =~ "a link or outside the template directory"
    end
  end

  test "a part file larger than a template may be is shown unavailable", %{tmp_dir: root} do
    seed(root)
    put(root, "order_offer", "html.et.html", String.duplicate("a", Overrides.max_bytes() + 1))

    view = mount_editor(root)
    select(view, "order_offer")

    assert has_element?(view, "#editor-part-html-invalid")
    assert render(view) =~ "larger than 256 KiB"
  end

  describe "the preview's iframe" do
    test "is sandboxed, sends no referrer and loads nothing from outside", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      iframe = view |> element("#editor-preview iframe") |> render()
      assert iframe =~ ~s(sandbox="")
      assert iframe =~ ~s(referrerpolicy="no-referrer")

      assert iframe =~
               ~s(csp="default-src &#39;none&#39;; img-src data:; style-src &#39;unsafe-inline&#39;")
    end

    test "loads images from the origins the host names, and only those", %{tmp_dir: root} do
      seed(root)

      view =
        mount_editor(root, %{
          preview_image_origins: ["https://shop.example.com", "bad origin; script-src *"]
        })

      select(view, "order_offer")

      iframe = view |> element("#editor-preview iframe") |> render()
      assert iframe =~ "img-src data: https://shop.example.com;"
      refute iframe =~ "script-src"
    end
  end

  describe "the module's converter limits" do
    test "too large and too slow are told in words", %{tmp_dir: root} do
      seed(root)

      for {reason, words} <- [too_large: "larger than 256 KiB", timeout: "it took too long"] do
        view =
          mount_editor(root, %{convert: %{to_text: fn _format, _source -> {:error, reason} end}})

        select(view, "order_offer")

        html = convert(view, "to_text", %{markdown: "# Hi"})

        assert html =~ "Not converted: #{words}"
      end
    end
  end

  test "an after_write warning: saved, and the warning shown", %{tmp_dir: root} do
    seed(root)

    view =
      mount_editor(root, %{
        after_write: fn _paths -> {:warning, "order_offer/subject.et.txt: mode not set"} end
      })

    select(view, "order_offer")
    html = save(view, %{subject: "Uus"})

    assert File.read!(Path.join([root, "order_offer", "subject.et.txt"])) == "Uus"
    assert html =~ "alert-warning"
    assert html =~ "Saved."
    assert html =~ "order_offer/subject.et.txt: mode not set"
  end
end
