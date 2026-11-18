defmodule PhoenixKitTemplatesEditor.LanguagesTest do
  use ExUnit.Case, async: true

  alias PhoenixKitTemplatesEditor.Languages

  describe "items/2" do
    test "the config's codes in order, each by its own name, flagged by PhoenixKit's list, Default last" do
      assert [
               %{code: "et", name: "Eesti", flag: "🇪🇪"},
               %{code: "ru", name: "Русский"},
               %{code: "en", name: "English", flag: "🇺🇸"},
               %{code: "", name: "По умолчанию"}
             ] = Languages.items(["et", "ru", "en", nil], "По умолчанию")
    end

    test "the files keep their base code: en is looked up as en-US and shown as English, never renamed" do
      assert [%{code: "en", name: "English"}] = Languages.items(["en"], "Default")
    end

    test "no Default entry unless the files without a language are a tab" do
      refute Enum.any?(Languages.items(["et", "ru"], "Default"), &(&1.code == ""))
    end

    test "only the files without a language: the Default alone" do
      assert [%{code: "", name: "Default"}] = Languages.items([nil], "Default")
    end

    test "a code PhoenixKit does not know is shown as its upper-cased code, flag-less" do
      assert [%{code: "xx", name: "XX", flag: nil}] = Languages.items(["xx"], "Default")
    end
  end

  test "languages/1 has no Default" do
    assert [%{code: "et"}, %{code: "en"}] = Languages.languages(["et", "en"])
  end
end
