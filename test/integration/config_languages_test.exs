defmodule PhoenixKitTemplatesEditor.Integration.ConfigLanguagesTest do
  use PhoenixKitTemplatesEditor.DataCase, async: false

  alias PhoenixKit.Modules.Languages
  alias PhoenixKitTemplatesEditor.Config

  @moduletag :tmp_dir

  test "without locales, the enabled PhoenixKit languages are the tabs, by base code",
       %{tmp_dir: tmp_dir} do
    {:ok, _} = Languages.enable_system()
    {:ok, _} = Languages.add_language("et")
    {:ok, _} = Languages.set_default_language("et")

    assert {:ok, %Config{base_locale: "et", locales: locales}} = Config.load(root: tmp_dir)
    assert Enum.sort(locales) == ["en", "et"]
  end

  test "without locales or base_locale, PhoenixKit's default language is the base",
       %{tmp_dir: tmp_dir} do
    {:ok, _} = Languages.enable_system()

    assert {:ok, %Config{base_locale: "en", locales: ["en"]}} = Config.load(root: tmp_dir)
  end

  test "a base_locale PhoenixKit does not have is added to the derived locales",
       %{tmp_dir: tmp_dir} do
    {:ok, _} = Languages.enable_system()

    assert {:ok, %Config{base_locale: "ru", locales: ["ru", "en"]}} =
             Config.load(root: tmp_dir, base_locale: "ru")
  end

  test "Languages switched off: only the base locale", %{tmp_dir: tmp_dir} do
    assert {:ok, %Config{base_locale: "en", locales: ["en"]}} = Config.load(root: tmp_dir)
  end
end
