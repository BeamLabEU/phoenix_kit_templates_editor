defmodule PhoenixKitTemplatesEditor.Web.EditorModuleEmailsDbTest do
  # An email with an active database template of the Emails module: the
  # red notice that the row, not the file, is sent, and a
  # file made from the row by that module's export. The provider and the
  # export are the application environment's, so not async.
  use PhoenixKitTemplatesEditor.EditorCase, async: false

  alias PhoenixKitTemplatesEditor.Test.FakeProvider
  alias PhoenixKitTemplatesEditor.Test.FakeTemplateExport

  @invoice %{
    name: "billing_invoice",
    label: "Invoice",
    defaults: %{subject: "Invoice", text: "Pay"},
    variables: %{}
  }

  setup do
    Application.put_env(:phoenix_kit_templates_editor, :template_export, FakeTemplateExport)
    on_exit(fn -> Application.delete_env(:phoenix_kit_templates_editor, :template_export) end)

    FakeProvider.put_db_templates(%{
      "billing_invoice" => %{
        name: "billing_invoice",
        is_system: false,
        subject: %{"en" => "Invoice from the row", "et" => "Arve reast"},
        text_body: %{"en" => "Row text"},
        html_body: %{"en" => "<p>Row</p>"}
      }
    })

    :ok
  end

  defp mount_modules(root, opts \\ %{}) do
    mount_editor(
      root,
      Map.merge(
        %{
          module_emails: [@invoice],
          reserved_names: ["billing_invoice"],
          overridable: :all
        },
        opts
      )
    )
  end

  test "no file yet: the row is what is sent, and a file can be made from it",
       %{tmp_dir: root} do
    seed(root)
    view = mount_modules(root)

    view
    |> element("#editor-module-emails [phx-click=select_module][phx-value-name=billing_invoice]")
    |> render_click()

    assert has_element?(view, "#editor-module-email-sources-db")

    html = view |> element("#editor-module-create-db") |> render_click()

    assert html =~ "database template"

    assert File.read!(Path.join([root, "billing_invoice", "subject.txt"])) ==
             "Invoice from the row"

    assert File.read!(Path.join([root, "billing_invoice", "subject.et.txt"])) == "Arve reast"
    assert has_element?(view, "#editor-sources-db")
  end

  test "with a file: the notice says the file is not what is sent", %{tmp_dir: root} do
    seed(root)
    put(root, "billing_invoice", "subject.et.txt", "Arve")
    view = mount_modules(root)

    view
    |> element("#editor-module-emails [phx-click=select][phx-value-name=billing_invoice]")
    |> render_click()

    assert view |> element("#editor-sources-db") |> render() =~ "not these files"
  end

  test "read only: no button for the row either", %{tmp_dir: root} do
    seed(root)
    view = mount_modules(root, %{editable: false})

    view
    |> element("#editor-module-emails [phx-click=select_module][phx-value-name=billing_invoice]")
    |> render_click()

    refute has_element?(view, "#editor-module-create-db")
    view |> with_target("#editor") |> render_click("override_db", %{"name" => "billing_invoice"})
    refute File.exists?(Path.join(root, "billing_invoice"))
  end
end
