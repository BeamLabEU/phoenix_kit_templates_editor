defmodule PhoenixKitTemplatesEditor.Web.SectionTest do
  # What the page mounts: the section reads the host's config, says what is
  # wrong with a broken one, says why the files are read only, and mounts the
  # editor with everything the config says. It no longer carries an
  # introduction, hints or the project's own notes. Writing needs the module
  # enabled and a permission — a database — so here the editor is always
  # read-only (see test/integration/section_*_test.exs for the rest).
  #
  # Not async: the section reads `config :phoenix_kit_templates_editor`.
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest
  import PhoenixKitTemplatesEditor.SectionCase

  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Web.Section

  @moduletag :tmp_dir

  setup %{tmp_dir: root} do
    on_exit(fn -> Overrides.reset_cache([root]) end)
    put(root, "shop_offer", "label.en.txt", "Price offer")
    put(root, "shop_offer", "subject.en.txt", "Offer")
    put(root, "shop_offer", "text.en.txt", "Hello")
    put(root, "_header-shop", "html.html", "<b>Shop</b>")
    put(root, "other_mail", "text.txt", "not ours")
    :ok
  end

  defp base_config(root, values \\ []) do
    configure(
      Keyword.merge(
        [root: root, name_prefixes: ["shop_", "_header-shop"], locales: ["en", "et"]],
        values
      )
    )
  end

  test "a broken config shows what is wrong instead of crashing the page",
       %{tmp_dir: tmp_dir} do
    configure(root: tmp_dir, editable: "true")

    html = render_component(Section, id: "templates_editor")

    assert html =~ "alert-error"
    assert html =~ "editable"
    refute html =~ tmp_dir
  end

  describe "read only" do
    test "the files are listed by the config's prefixes, nothing can be written",
         %{tmp_dir: root} do
      base_config(root)
      view = mount_section()

      assert has_element?(view, "#templates-editor button[phx-value-name=shop_offer]")
      assert has_element?(view, "#templates-editor button[phx-value-name=_header-shop]")
      refute has_element?(view, "#templates-editor button[phx-value-name=other_mail]")
      refute has_element?(view, "#templates-editor-create")
      refute has_element?(view, "#templates-editor-hints")
      refute has_element?(view, "#templates-editor-uncommitted-check")
    end

    test "editable, but nobody who may write is acting: read only, and said",
         %{tmp_dir: root} do
      base_config(root, editable: true)
      view = mount_section()

      assert has_element?(view, "#templates-editor-no-write")
      refute has_element?(view, "#templates-editor-create")
    end

    test "the config's languages are the tabs; email_fallback: false drops an email's Fallback",
         %{tmp_dir: root} do
      base_config(root, locales: ["en", "ru"], email_fallback: false)
      view = mount_section()

      view |> element("#templates-editor button[phx-value-name=shop_offer]") |> render_click()

      assert has_element?(view, "#templates-editor [phx-click=locale][phx-value-language=en]")
      assert has_element?(view, "#templates-editor [phx-click=locale][phx-value-language=ru]")
      refute has_element?(view, "#templates-editor [phx-click=locale][phx-value-language='']")
    end
  end

  describe "layouts" do
    setup %{tmp_dir: root} do
      put(root, "_header", "html.html", "<b>Shared</b>")
      put(root, "_footer-shop-partner", "html.html", "<b>Partner</b>")
      put(root, "_footer-shopx", "html.html", "<b>Not ours</b>")
      put(root, "shop_offer", "layout.txt", "shop-partner")
      :ok
    end

    test "the config's layout groups: the default first, the namespace exact, the email's choice",
         %{tmp_dir: root} do
      base_config(root, name_prefixes: ["shop_"], layout_group: "shop")
      view = mount_section()

      assert has_element?(view, "#templates-editor-layout-shop", "default")
      assert has_element?(view, "#templates-editor-layout-shop [phx-value-name=_header-shop]")

      assert has_element?(
               view,
               "#templates-editor-layout-shop-partner [phx-value-name=_footer-shop-partner]"
             )

      refute has_element?(view, "[phx-value-name=_footer-shopx]")
      refute has_element?(view, "[phx-value-name=_header]")

      view |> element("#templates-editor button[phx-value-name=shop_offer]") |> render_click()
      assert has_element?(view, "#templates-editor-email-layout-current", "shop-partner")
    end

    test "the shared parts with shared_layout_editable: true", %{tmp_dir: root} do
      base_config(root, layout_group: "shop", shared_layout_editable: true)

      assert has_element?(mount_section(), "#templates-editor-shared [phx-value-name=_header]")
    end
  end

  describe "the project's notes" do
    test "are not on the page: no block, and nothing of them in it", %{tmp_dir: root} do
      base_config(root)
      File.write!(Path.join(root, "README.ru.md"), "# Заметки\n\nSECRET-NOTE")
      File.write!(Path.join(root, "README.md"), "# Notes\n\nSECRET-NOTE")

      view = mount_section(locale: "ru")

      refute has_element?(view, "#templates-editor-readme")
      refute render(view) =~ "SECRET-NOTE"
    end
  end

  test "no introduction and no hints on the page", %{tmp_dir: root} do
    base_config(root, editable: true)
    view = mount_section()

    refute has_element?(view, "#templates-editor-intro")
    refute has_element?(view, "#templates-editor-hints")
  end

  test "catalog: true with a root core does not read: said on the tab", %{tmp_dir: root} do
    previous = Application.fetch_env(:phoenix_kit, :template_paths)
    Application.put_env(:phoenix_kit, :template_paths, [Path.join(root, "elsewhere")])

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:phoenix_kit, :template_paths, value)
        :error -> Application.delete_env(:phoenix_kit, :template_paths)
      end
    end)

    base_config(root, catalog: true)
    view = mount_section()

    assert has_element?(view, "#templates-editor-catalog-off")
    refute render(view) =~ root
  end

  test "Estonian: the read-only notice in the page's language", %{tmp_dir: root} do
    base_config(root, editable: true)
    view = mount_section(locale: "et")

    assert has_element?(view, "#templates-editor-no-write", "Mallide redaktor on välja lülitatud")
  end
end
