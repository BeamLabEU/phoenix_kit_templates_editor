defmodule PhoenixKitTemplatesEditor.Web.SectionTest do
  # The tab core mounts with nothing but its id: it reads the host's config,
  # says what is wrong with a broken one, introduces the files, shows the
  # project's own notes (README beside the templates) and mounts the editor
  # with everything the config says. Writing needs the module enabled and a
  # permission — a database — so here the editor is always read-only (see
  # test/integration/section_*_test.exs for the rest).
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

      assert has_element?(view, "#templates-editor-intro", "Read only on this server")
      assert has_element?(view, "#templates-editor button[phx-value-name=shop_offer]")
      assert has_element?(view, "#templates-editor button[phx-value-name=_header-shop]")
      refute has_element?(view, "#templates-editor button[phx-value-name=other_mail]")
      refute has_element?(view, "#templates-editor-create")
      refute has_element?(view, "#templates-editor-hints")
      refute has_element?(view, "#templates-editor-uncommitted-check")
    end

    test "editable, but no scope tells the section who is acting: read only, and said",
         %{tmp_dir: root} do
      base_config(root, editable: true)
      view = mount_section()

      assert has_element?(view, "#templates-editor-intro", "A change saved here changes the file")
      assert has_element?(view, "#templates-editor-no-write")
      refute has_element?(view, "#templates-editor-create")
    end

    test "the config's languages are the tabs; email_fallback: false drops an email's Fallback",
         %{tmp_dir: root} do
      base_config(root, locales: ["en", "ru"], email_fallback: false)
      view = mount_section()

      view |> element("#templates-editor button[phx-value-name=shop_offer]") |> render_click()

      assert has_element?(view, "#templates-editor [role=tab][phx-value-locale=en]")
      assert has_element?(view, "#templates-editor [role=tab][phx-value-locale=ru]")
      refute has_element?(view, "#templates-editor [role=tab][phx-value-locale='']")
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
    test "README.<page language>.md beside the templates, as sanitized Markdown",
         %{tmp_dir: root} do
      base_config(root)
      File.write!(Path.join(root, "README.ru.md"), "# Заметки\n\n<script>alert(1)</script>Текст")
      File.write!(Path.join(root, "README.md"), "# Notes")

      view = mount_section(locale: "ru")

      html = view |> element("#templates-editor-readme") |> render()
      assert html =~ "Заметки"
      refute html =~ "<script"
    end

    test "else README.<base_locale>.md, else README.md", %{tmp_dir: root} do
      base_config(root, base_locale: "et")
      File.write!(Path.join(root, "README.et.md"), "# Märkmed")
      File.write!(Path.join(root, "README.md"), "# Notes")

      assert mount_section(locale: "ru") |> element("#templates-editor-readme") |> render() =~
               "Märkmed"

      File.rm!(Path.join(root, "README.et.md"))

      assert mount_section(locale: "ru") |> element("#templates-editor-readme") |> render() =~
               "Notes"
    end

    test "none: no notes; a linked README is not read", %{tmp_dir: root} do
      base_config(root)
      refute has_element?(mount_section(), "#templates-editor-readme")

      File.write!(Path.join(root, "secret.txt"), "SECRET")
      File.ln_s!("secret.txt", Path.join(root, "README.md"))

      view = mount_section()
      refute has_element?(view, "#templates-editor-readme")
      refute render(view) =~ "SECRET"
    end
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

  test "Estonian: the intro in the page's language", %{tmp_dir: root} do
    base_config(root)
    view = mount_section(locale: "et")

    assert has_element?(view, "#templates-editor-intro", "Selles serveris ainult vaatamiseks")
  end
end
