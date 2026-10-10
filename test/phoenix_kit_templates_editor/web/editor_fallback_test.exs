defmodule PhoenixKitTemplatesEditor.Web.EditorFallbackTest do
  # `email_fallback: false` — a host that sends an email only in its own
  # languages: an email's locale-less files are never used.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  defp fallback_tab?(view), do: has_element?(view, "#editor [role=tab][phx-value-locale='']")

  defp selected_tab?(view, label),
    do: has_element?(view, "#editor [role=tab][aria-selected=true]", label)

  defp seed_fallback(root) do
    seed(root)
    put(root, "order_offer", "subject.txt", "Fallback subject\n")
    put(root, "order_offer", "text.txt", "Fallback text\n")
    put(root, "order_offer", "layout.txt", "shop\n")
    put(root, "order_offer", "audience.txt", "partner\n")
  end

  defp open_fallback(view) do
    select(view, "order_offer")
    tab(view, "")
  end

  test "by default an email has its Fallback tab, editable", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root)
    select(view, "order_offer")

    assert fallback_tab?(view)
    tab(view, "")
    assert has_element?(view, "#editor-parts")
    refute has_element?(view, "#editor-fallback-unused")
  end

  describe "with email_fallback: false" do
    test "an email without locale-less files has no Fallback tab", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "layout.txt", "shop\n")
      view = mount_editor(root, %{email_fallback: false})
      select(view, "order_offer")

      refute fallback_tab?(view)
      assert has_element?(view, "#editor [role=tab][phx-value-locale='en']")

      # A forged switch to the fallback is no tab: the save goes to et.
      render_click(with_target(view, "#editor"), "locale", %{"locale" => ""})
      save(view, %{subject: "Uus"})

      assert File.read!(Path.join([root, "order_offer", "subject.et.txt"])) == "Uus"
      refute File.exists?(Path.join([root, "order_offer", "subject.txt"]))
    end

    test "a header, footer or layout keeps its Fallback tab", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{email_fallback: false})
      select(view, "_header-shop")

      assert fallback_tab?(view)
      assert selected_tab?(view, "Fallback")
      assert has_element?(view, "#editor-parts")
      refute has_element?(view, "#editor-fallback-unused")
    end

    test "a new email has no Fallback tab", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{email_fallback: false})
      create(view, "order_new")

      refute fallback_tab?(view)
      assert selected_tab?(view, "et")
    end

    test "locale-less files left over are shown read-only, marked as not used",
         %{tmp_dir: root} do
      seed_fallback(root)
      view = mount_editor(root, %{email_fallback: false})
      select(view, "order_offer")

      # Opens on its first language, not on the files nobody reads.
      assert selected_tab?(view, "et")
      assert fallback_tab?(view)
      assert view |> element("#editor [role=tab][phx-value-locale='']") |> render() =~ "not used"

      tab(view, "")

      refute has_element?(view, "#editor-parts")
      assert render(view) =~ "Fallback subject"
      assert view |> element("#editor-fallback-unused") |> render() =~ "not used"
      assert has_element?(view, "#editor-fallback-delete")
    end

    test "a forged save to the unused fallback writes nothing", %{tmp_dir: root} do
      seed_fallback(root)
      view = mount_editor(root, %{email_fallback: false, convert: %{to_text: {Host, :to_text}}})
      open_fallback(view)
      target = with_target(view, "#editor")

      render_submit(target, "save", %{"parts" => %{"subject" => "Hacked"}})

      render_submit(target, "save", %{
        "action" => "to_text",
        "parts" => %{"markdown" => "**x**"}
      })

      assert File.read!(Path.join([root, "order_offer", "subject.txt"])) == "Fallback subject\n"
      refute_received {:after_write, _paths}
    end

    test "deletes the locale-less parts after a confirmation, and nothing else",
         %{tmp_dir: root} do
      seed_fallback(root)
      view = mount_editor(root, %{email_fallback: false})
      open_fallback(view)
      dir = Path.join(root, "order_offer")

      view |> element("#editor-fallback-delete") |> render_click()
      assert File.exists?(Path.join(dir, "subject.txt"))
      view |> element("#editor-fallback-delete-cancel") |> render_click()
      refute has_element?(view, "#editor-fallback-delete-confirm")

      view |> element("#editor-fallback-delete") |> render_click()
      html = view |> element("#editor-fallback-delete-confirm") |> render_click()

      assert html =~ "Deleted"
      refute File.exists?(Path.join(dir, "subject.txt"))
      refute File.exists?(Path.join(dir, "text.txt"))
      # The layout choice, the host's own file and the languages stay.
      assert File.read!(Path.join(dir, "layout.txt")) == "shop\n"
      assert File.read!(Path.join(dir, "audience.txt")) == "partner\n"
      assert File.read!(Path.join(dir, "subject.et.txt")) == "Pakkumine {{order_number}}\n"

      assert_received {:after_change, "order_offer"}
      refute fallback_tab?(view)
      assert selected_tab?(view, "et")
      assert has_element?(view, "#editor-parts")
    end

    test "the delete is refused read-only or without permission", %{tmp_dir: root} do
      seed_fallback(root)
      test_pid = self()

      read_only = mount_editor(root, %{email_fallback: false, editable: false})
      open_fallback(read_only)
      refute has_element?(read_only, "#editor-fallback-delete")
      target = with_target(read_only, "#editor")

      assert render_click(target, "delete_fallback", %{}) =~ "read-only"
      assert render_click(target, "confirm_delete_fallback", %{}) =~ "read-only"

      denying = fn action ->
        send(test_pid, {:authorize, action})
        {:error, :forbidden}
      end

      view = mount_editor(root, %{email_fallback: false})
      open_fallback(view)
      view |> element("#editor-fallback-delete") |> render_click()
      send(view.pid, {:put, %{authorize: denying}})

      assert view |> element("#editor-fallback-delete-confirm") |> render_click() =~
               "not allowed"

      assert_received {:authorize, :delete}
      refute has_element?(view, "#editor-fallback-delete-confirm")
      assert File.exists?(Path.join([root, "order_offer", "subject.txt"]))
      assert File.exists?(Path.join([root, "order_offer", "text.txt"]))
    end

    test "a forged fallback delete where the fallback is used deletes nothing",
         %{tmp_dir: root} do
      seed_fallback(root)
      view = mount_editor(root)
      open_fallback(view)
      target = with_target(view, "#editor")

      render_click(target, "delete_fallback", %{})
      render_click(target, "confirm_delete_fallback", %{})

      assert File.exists?(Path.join([root, "order_offer", "subject.txt"]))

      header = mount_editor(root, %{email_fallback: false})
      select(header, "_header-shop")
      target = with_target(header, "#editor")

      render_click(target, "delete_fallback", %{})
      render_click(target, "confirm_delete_fallback", %{})

      assert File.exists?(Path.join([root, "_header-shop", "html.html"]))
    end
  end
end
