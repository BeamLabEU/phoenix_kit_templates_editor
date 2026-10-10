defmodule PhoenixKitTemplatesEditor.Web.EditorConflictTest do
  # Two people, or a person and git: a part's file is
  # fingerprinted when the form is given it, and a save of that part is
  # refused when the file on disk is no longer what the form was given —
  # changed, created or deleted meanwhile. "Reload" drops the cache and
  # reads the list and the parts again.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  defp path(root, file), do: Path.join([root, "order_offer", file])

  # Another session writes, and the host re-renders the editor.
  defp elsewhere(view, root, file, content) do
    case content do
      nil -> File.rm!(path(root, file))
      content -> File.write!(path(root, file), content)
    end

    Overrides.reset_cache([root])
    send(view.pid, {:put, %{tick: System.unique_integer()}})
    _ = render(view)
  end

  test "a part changed on disk since it was opened is not saved over", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root)
    select(view, "order_offer")
    elsewhere(view, root, "subject.et.txt", "Teine sessioon\n")

    html = save(view, %{subject: "Minu muudatus"})

    assert html =~ "changed on disk"
    assert File.read!(path(root, "subject.et.txt")) == "Teine sessioon\n"
    assert view |> element("#editor-conflict") |> render() =~ "Teine sessioon"
    assert field(view, :subject) == "Minu muudatus"
    refute_received {:after_write, _paths}
  end

  test "a file created or deleted meanwhile counts as changed", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root)
    select(view, "order_offer")
    elsewhere(view, root, "markdown.et.md", "**Kelleltki**")
    elsewhere(view, root, "text.et.txt", nil)

    html = save(view, %{markdown: "**Minu**", text: "Minu tekst"})

    assert html =~ "changed on disk"
    assert File.read!(path(root, "markdown.et.md")) == "**Kelleltki**"
    refute File.exists?(path(root, "text.et.txt"))
    assert view |> element("#editor-conflict") |> render() =~ "no file"
  end

  test "a part the user did not touch is not in the way", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root)
    select(view, "order_offer")
    elsewhere(view, root, "subject.et.txt", "Teine sessioon\n")

    assert save(view, %{text: "Uus tekst"}) =~ "Saved."
    assert File.read!(path(root, "text.et.txt")) == "Uus tekst"
  end

  test "after a save the next save of the same part goes through", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root)
    select(view, "order_offer")

    assert save(view, %{subject: "Üks"}) =~ "Saved."
    assert save(view, %{subject: "Kaks"}) =~ "Saved."
    assert File.read!(path(root, "subject.et.txt")) == "Kaks"
  end

  test "Reload gives the form what is on disk, and then it saves", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root)
    select(view, "order_offer")
    elsewhere(view, root, "subject.et.txt", "Teine sessioon\n")
    save(view, %{subject: "Minu muudatus"})

    view |> element("#editor-reload") |> render_click()

    refute has_element?(view, "#editor-conflict")
    assert field(view, :subject) == "Teine sessioon\n"
    assert save(view, %{subject: "Minu muudatus"}) =~ "Saved."
    assert File.read!(path(root, "subject.et.txt")) == "Minu muudatus"
  end

  test "Reload drops the cache: a template put on disk by hand is listed", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root)
    refute has_element?(view, "#editor [phx-value-name=order_new]")

    put(root, "order_new", "subject.et.txt", "Uus")
    view |> element("#editor-reload") |> render_click()

    assert has_element?(view, "#editor [phx-click=select][phx-value-name=order_new]")
  end
end
