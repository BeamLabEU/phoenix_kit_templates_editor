defmodule PhoenixKitTemplatesEditor.Web.EditorI18nTest do
  # The editor speaks the page's language: core puts it on the module's
  # Gettext backend; the test host does the same from its session.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  @catalogs Path.expand("../../../priv/gettext", __DIR__)

  defp messages(path) do
    for message <- Expo.PO.parse_file!(path).messages,
        into: %{},
        do: {IO.iodata_to_binary(message.msgid), IO.iodata_to_binary(message.msgstr)}
  end

  defp placeholders(text), do: ~r/%\{\w+\}/ |> Regex.scan(text) |> List.flatten() |> Enum.sort()

  for locale <- ["et", "ru"] do
    test "every message has a #{locale} translation with the same placeholders" do
      template = messages(Path.join(@catalogs, "default.pot"))
      translated = messages(Path.join([@catalogs, unquote(locale), "LC_MESSAGES", "default.po"]))

      for {msgid, _empty} <- template do
        msgstr = Map.get(translated, msgid, "")
        assert msgstr != "", "no #{unquote(locale)} translation for #{inspect(msgid)}"

        assert placeholders(msgstr) == placeholders(msgid),
               "placeholders differ in the #{unquote(locale)} translation of #{inspect(msgid)}"
      end
    end
  end

  test "Russian: the form, the tabs, a notice and the incomplete flag", %{tmp_dir: root} do
    seed(root)
    put(root, "order_new", "subject.et.txt", "Teema")
    view = mount_editor(root, %{locale: "ru"})

    assert view |> element("#editor-messages-incomplete-order_new") |> render() =~
             "Не будет предложено к отправке: нет темы или текста письма на языке et."

    html = select(view, "order_offer")

    assert html =~ "Письма"
    assert html =~ "Оформления"
    assert html =~ "унаследован: стандартный из ядра"
    assert html =~ "Название в списках. В письме не отправляется."
    assert has_element?(view, "#editor [role=tab][phx-value-locale='']", "Общий")
    assert has_element?(view, "#editor-parts button[value=save]", "Сохранить")

    assert save(view, %{subject: "Новая тема"}) =~ "Сохранено."
  end

  test "Estonian: the form and a refusal", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root, %{locale: "et", authorize: fn _action -> {:error, :forbidden} end})

    html = select(view, "order_offer")

    assert html =~ "Kirjad"
    assert has_element?(view, "#editor [role=tab][phx-value-locale='']", "Üldine")
    assert has_element?(view, "#editor-parts button[value=save]", "Salvesta")

    assert save(view, %{subject: "Uus"}) =~
             "Teil pole õigust malle muuta: midagi ei muudetud."
  end

  test "a part title inside a notice is translated too", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root, %{locale: "ru"})
    select(view, "order_offer")

    html = save(view, %{html: String.duplicate("a", Overrides.max_bytes() + 1)})

    assert html =~ "Не сохранено: HTML: больше 256 КиБ"
  end
end
