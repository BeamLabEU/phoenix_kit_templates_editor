defmodule PhoenixKitTemplatesEditor.I18nSmokeTest do
  # `Gettext.put_locale/2` mutates the process dictionary.
  use ExUnit.Case, async: false

  alias PhoenixKitTemplatesEditor.Gettext, as: Backend

  setup do
    original = Gettext.get_locale(Backend)
    on_exit(fn -> Gettext.put_locale(Backend, original) end)
    :ok
  end

  for {locale, title, name} <- [
        {"et", "Kirjade mallid", "Mallide redaktor"},
        {"ru", "Шаблоны писем", "Редактор шаблонов"}
      ] do
    test "the Settings item label and the module name translate to #{locale}" do
      [%{label: label, gettext_backend: backend}] = PhoenixKitTemplatesEditor.settings_tabs()

      assert label == "Email templates"

      assert Gettext.with_locale(backend, unquote(locale), fn ->
               Gettext.dgettext(backend, "default", label)
             end) == unquote(title)

      Gettext.put_locale(Backend, unquote(locale))
      assert PhoenixKitTemplatesEditor.module_name() == unquote(name)
    end

    test "the permission label has a #{locale} translation" do
      %{label: label, gettext_backend: backend} =
        PhoenixKitTemplatesEditor.permission_metadata()

      assert Gettext.with_locale(backend, unquote(locale), fn ->
               Gettext.dgettext(backend, "default", label)
             end) == unquote(name)
    end
  end

  test "an unknown locale falls back to the English msgid" do
    [%{label: label, gettext_backend: backend}] = PhoenixKitTemplatesEditor.settings_tabs()

    assert Gettext.with_locale(backend, "xx", fn ->
             Gettext.dgettext(backend, "default", label)
           end) ==
             "Email templates"
  end
end
