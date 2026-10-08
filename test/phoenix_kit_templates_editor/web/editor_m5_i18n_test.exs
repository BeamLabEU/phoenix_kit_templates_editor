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

  # Spec §4.10 Б9: three braces refused where no variable may take them —
  # a sentence of its own, not "only for" with "none here" put in.
  for {locale, none, allowed} <- [
        {"en", "Write them with two braces: no variable is written with three here.",
         "Write them with two braces; three are only for {{{documents_list}}}."},
        {"ru", "Пишите в двух фигурных скобках: здесь ни одна переменная не пишется в трёх.",
         "Пишите в двух фигурных скобках; три — только для {{{documents_list}}}."},
        {"et",
         "Kirjutage need kahe looksulguga: siin ei kirjutata ühtegi muutujat kolme looksulguga.",
         "Kirjutage need kahe looksulguga; kolm on lubatud ainult muutujatele {{{documents_list}}}."}
      ] do
    test "three braces refused in #{locale}, with and without variables allowed them",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{locale: unquote(locale)})
      select(view, "order_offer")

      html = save(view, %{html: "<div>{{{order_number}}}</div>"})
      assert html =~ unquote(none)

      view = mount_editor(root, %{locale: unquote(locale), raw_variables: ["documents_list"]})
      select(view, "order_offer")

      html = save(view, %{html: "<div>{{{order_number}}}</div>"})
      assert html =~ unquote(allowed)
    end
  end
end
