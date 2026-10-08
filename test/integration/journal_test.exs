defmodule PhoenixKitTemplatesEditor.Integration.JournalTest do
  # The activity log entries a change made through the tab leaves.
  use PhoenixKitTemplatesEditor.DataCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import PhoenixKitTemplatesEditor.SectionCase

  alias PhoenixKit.Activity.Entry
  alias PhoenixKit.Templates.Overrides

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    root = Path.join(tmp, "templates")
    on_exit(fn -> Overrides.reset_cache([root]) end)
    put(root, "shop_offer", "subject.en.txt", "Offer")

    configure(root: root, editable: true, name_prefixes: ["shop_"], locales: ["en"])
    {:ok, _} = PhoenixKitTemplatesEditor.enable_system()
    %{root: root}
  end

  defp entries do
    Repo.all(
      from(e in Entry,
        where: e.module == "templates_editor",
        order_by: [asc: e.inserted_at]
      )
    )
  end

  test "a save, a copy and a delete", %{root: root} do
    view = mount_section(scope: writer())
    view |> element("#templates-editor button[phx-value-name=shop_offer]") |> render_click()

    view |> form("#templates-editor-parts", parts: %{subject: "New offer"}) |> render_submit()

    view
    |> form("#templates-editor-create", create: %{name: "shop_copy", copy_from: "shop_offer"})
    |> render_submit()

    view |> element("#templates-editor-delete") |> render_click()
    view |> element("#templates-editor-delete-confirm") |> render_click()

    assert [saved, copied, deleted] = entries()

    assert saved.action == "templates_editor.file_saved"
    assert saved.resource_type == "email_template"

    assert saved.metadata == %{
             "template" => "shop_offer",
             "part" => "subject",
             "locale" => "en",
             "diff" => "@1:1\n- O\n+ New o"
           }

    assert copied.action == "templates_editor.template_copied"
    assert copied.metadata == %{"template" => "shop_copy", "from" => "shop_offer"}

    assert deleted.action == "templates_editor.template_deleted"
    assert deleted.metadata == %{"template" => "shop_copy"}
    refute File.exists?(Path.join(root, "shop_copy"))
  end

  test "a refused save leaves nothing" do
    view = mount_section(scope: scope(["settings", "templates_editor"]))
    view |> element("#templates-editor button[phx-value-name=shop_offer]") |> render_click()

    assert entries() == []
  end
end
