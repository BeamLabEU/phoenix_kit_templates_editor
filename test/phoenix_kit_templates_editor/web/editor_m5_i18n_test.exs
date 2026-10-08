defmodule PhoenixKitTemplatesEditor.Web.EditorM5I18nTest do
  # The module-emails section, the variables panel and the save checks
  # speak the page's language too.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  @invoice %{name: "billing_invoice", label: "Invoice", defaults: %{text: "T"}}

  test "Russian", %{tmp_dir: root} do
    seed(root)

    view =
      mount_editor(root, %{
        locale: "ru",
        module_emails: [@invoice],
        reserved_names: ["billing_invoice"],
        overridable: :all
      })

    assert view |> element("#editor-module-emails") |> render() =~ "Письма модулей"
    assert has_element?(view, "#editor-reload", "Перечитать")

    select(view, "order_offer")
    assert view |> element("#editor-variables") |> render() =~ "только в Markdown"
    save(view, %{text: "{{site_url}}"})
    assert has_element?(view, "#editor-confirm-variables-save", "Всё равно сохранить")

    view
    |> element("#editor-module-emails [phx-click=select_module][phx-value-name=billing_invoice]")
    |> render_click()

    assert has_element?(
             view,
             "#editor-module-create-default",
             "Создать файл из встроенного текста"
           )
  end

  test "Estonian", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root, %{locale: "et"})
    select(view, "order_offer")

    assert save(view, %{subject: "Üks\nKaks"}) =~ "teema peab olema üks rida"
    assert has_element?(view, "#editor-reload", "Laadi uuesti")
  end
end
