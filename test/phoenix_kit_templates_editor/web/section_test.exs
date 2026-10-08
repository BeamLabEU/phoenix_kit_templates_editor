defmodule PhoenixKitTemplatesEditor.Web.SectionTest do
  # Not async: the section reads `config :phoenix_kit_templates_editor`.
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias PhoenixKitTemplatesEditor.Web.Section

  @moduletag :tmp_dir

  setup do
    previous = Application.get_all_env(:phoenix_kit_templates_editor)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:phoenix_kit_templates_editor),
          do: Application.delete_env(:phoenix_kit_templates_editor, key)

      for {key, value} <- previous,
          do: Application.put_env(:phoenix_kit_templates_editor, key, value)
    end)
  end

  test "a broken config shows what is wrong instead of crashing the page",
       %{tmp_dir: tmp_dir} do
    Application.put_env(:phoenix_kit_templates_editor, :root, tmp_dir)
    Application.put_env(:phoenix_kit_templates_editor, :editable, "true")

    html = render_component(Section, id: "templates_editor")

    assert html =~ "alert-error"
    assert html =~ "editable"
    refute html =~ tmp_dir
  end

  test "a valid config renders the placeholder", %{tmp_dir: tmp_dir} do
    Application.put_env(:phoenix_kit_templates_editor, :root, tmp_dir)

    html = render_component(Section, id: "templates_editor")

    refute html =~ "alert-error"
    assert html =~ ~s(id="templates-editor-section")
  end
end
