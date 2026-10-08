defmodule PhoenixKitTemplatesEditor.JournalTest do
  # What a change leaves in PhoenixKit's activity log (spec §4.10 Б3): who,
  # the template, the part, the language and a short diff.
  use ExUnit.Case, async: true

  alias PhoenixKitTemplatesEditor.Journal

  describe "diff/2" do
    test "only the changed stretch, with where it starts" do
      assert Journal.diff("Hello, world!", "Hello, there!") == "@1:8\n- world\n+ there"
    end

    test "a new file and a deleted one" do
      assert Journal.diff(nil, "New") == "@1:1\n+ New"
      assert Journal.diff("Old", nil) == "@1:1\n- Old"
      assert Journal.diff(nil, nil) == ""
    end

    test "the line and column of the change" do
      assert Journal.diff("a\nbc\nd", "a\nbX\nd") == "@2:2\n- c\n+ X"
    end

    test "never more than about 500 characters, and never a broken character" do
      before = String.duplicate("ä", 2_000)
      diff = Journal.diff(before, "x" <> before)

      assert String.valid?(diff)
      assert String.length(diff) <= 520

      long = Journal.diff(String.duplicate("ö", 1_000), String.duplicate("ü", 1_000))
      assert String.valid?(long)
      assert String.length(long) <= 520
      assert long =~ "…"
    end
  end

  describe "metadata/1" do
    test "the template, the part, the language and the diff, as strings" do
      assert Journal.metadata(%{
               action: :file_saved,
               template: "shop_offer",
               part: :subject,
               locale: "et",
               before: "Old",
               after: "New"
             }) == %{
               "template" => "shop_offer",
               "part" => "subject",
               "locale" => "et",
               "diff" => "@1:1\n- Old\n+ New"
             }
    end

    test "only what the event has" do
      assert Journal.metadata(%{action: :template_copied, template: "b", from: "a"}) ==
               %{"template" => "b", "from" => "a"}

      assert Journal.metadata(%{action: :layout_set, template: "b", layout: nil}) ==
               %{"template" => "b", "layout" => nil}
    end
  end

  test "action/1 is namespaced by the module key" do
    assert Journal.action(:file_saved) == "templates_editor.file_saved"
  end
end
