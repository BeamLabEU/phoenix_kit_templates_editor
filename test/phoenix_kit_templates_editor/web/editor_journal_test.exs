defmodule PhoenixKitTemplatesEditor.Web.EditorJournalTest do
  # Every change on disk is told to the host's `journal` (spec §4.10 Б3):
  # what, which template, part and language, and the text before and after.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  defp mount_journalled(root, opts \\ %{}) do
    test_pid = self()

    mount_editor(
      root,
      Map.merge(
        %{
          journal: fn event -> send(test_pid, {:journal, event}) end,
          layout_group: "shop",
          layout_groups: ["shop"]
        },
        opts
      )
    )
  end

  test "a save: each part written or deleted", %{tmp_dir: root} do
    seed(root)
    view = mount_journalled(root)
    select(view, "order_offer")

    save(view, %{subject: "Uus teema", text: ""})

    assert_received {:journal,
                     %{
                       action: :file_saved,
                       template: "order_offer",
                       part: :subject,
                       locale: "et",
                       before: "Pakkumine {{order_number}}\n",
                       after: "Uus teema"
                     }}

    assert_received {:journal,
                     %{
                       action: :file_deleted,
                       part: :text,
                       before: "Tere!\n\n{{documents_list}}\n"
                     }}
  end

  test "nothing for a save that changed nothing or was refused", %{tmp_dir: root} do
    seed(root)
    view = mount_journalled(root)
    select(view, "order_offer")

    save(view, %{})
    save(view, %{text: "{{site_url}}"})

    refute_received {:journal, _event}
  end

  test "a copy, a template deleted, a layout chosen", %{tmp_dir: root} do
    seed(root)
    view = mount_journalled(root)

    create(view, "order_copy", "order_offer")

    assert_received {:journal,
                     %{action: :template_copied, template: "order_copy", from: "order_offer"}}

    view |> form("#editor-email-layout", email_layout: %{group: "shop"}) |> render_change()
    assert_received {:journal, %{action: :layout_set, template: "order_copy", layout: "shop"}}

    view |> element("#editor-delete") |> render_click()
    view |> element("#editor-delete-confirm") |> render_click()
    assert_received {:journal, %{action: :template_deleted, template: "order_copy"}}
  end

  test "a layout created and deleted", %{tmp_dir: root} do
    seed(root)
    view = mount_journalled(root)

    view
    |> form("#editor-layouts-create", layout_create: %{name: "shop-new", copy_from: "shop"})
    |> render_submit()

    assert_received {:journal, %{action: :layout_created, layout: "shop-new", from: "shop"}}

    view |> element("#editor-layout-shop-new_delete") |> render_click()
    view |> element("#editor-layouts-delete-confirm") |> render_click()
    assert_received {:journal, %{action: :layout_deleted, layout: "shop-new"}}
  end

  test "an email's unused fallback deleted", %{tmp_dir: root} do
    seed(root)
    put(root, "order_offer", "text.txt", "Vana")
    view = mount_journalled(root, %{email_fallback: false})
    select(view, "order_offer")
    tab(view, "")

    view |> element("#editor-fallback-delete") |> render_click()
    view |> element("#editor-fallback-delete-confirm") |> render_click()

    assert_received {:journal,
                     %{action: :fallback_deleted, template: "order_offer", parts: [:text]}}
  end

  test "a journal that fails is logged; the change stands", %{tmp_dir: root} do
    seed(root)

    log =
      capture_log(fn ->
        view = mount_editor(root, %{journal: fn _event -> raise "log down" end})
        select(view, "order_offer")
        assert save(view, %{subject: "Uus"}) =~ "Saved."
      end)

    assert log =~ "journal"
    assert File.read!(Path.join([root, "order_offer", "subject.et.txt"])) == "Uus"
  end
end
