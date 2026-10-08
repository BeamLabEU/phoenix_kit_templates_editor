defmodule PhoenixKitTemplatesEditor.Integration.SectionTest do
  # The tab with the module enabled: who may write (the config's `editable`
  # and the `templates_editor.write` permission, asked again on every
  # change), what a write leaves on disk, the list of what is not committed,
  # and the module's own preview.
  use PhoenixKitTemplatesEditor.DataCase, async: false

  import Phoenix.LiveViewTest
  import PhoenixKitTemplatesEditor.SectionCase

  alias PhoenixKit.Templates.Overrides

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    root = Path.join(tmp, "repo/priv/templates")
    on_exit(fn -> Overrides.reset_cache([root]) end)

    put(root, "shop_offer", "label.en.txt", "Price offer")
    put(root, "shop_offer", "subject.en.txt", "Offer {{order_number}}")
    put(root, "shop_offer", "text.en.txt", "Hello, {{customer_name}}!")
    put(root, "_header-shop", "html.html", "<div>SHOP-HEADER</div>")

    configure(
      root: root,
      editable: true,
      name_prefixes: ["shop_", "_header-shop"],
      locales: ["en"],
      layout_group: "shop",
      sample_variables: %{"order_number" => "37", "customer_name" => "Mari"}
    )

    {:ok, _} = PhoenixKitTemplatesEditor.enable_system()
    %{root: root, repo: Path.join(tmp, "repo")}
  end

  defp select(view, name),
    do: view |> element("#templates-editor button[phx-value-name=#{name}]") |> render_click()

  defp save(view, parts),
    do: view |> form("#templates-editor-parts", parts: parts) |> render_submit()

  defp git!(repo, args) do
    identity = ["-c", "user.name=Test", "-c", "user.email=test@example.com"]
    {_out, 0} = System.cmd("git", identity ++ ["-c", "commit.gpgsign=false" | args], cd: repo)
  end

  describe "who may write" do
    test "with the write permission: the form, and a save writes the file", %{root: root} do
      view = mount_section(scope: writer())
      select(view, "shop_offer")

      assert save(view, %{subject: "New offer"}) =~ "Saved."
      assert File.read!(Path.join([root, "shop_offer", "subject.en.txt"])) == "New offer"
      assert has_element?(view, "#templates-editor-hints")
    end

    test "without it: read only, and the tab says why", %{root: root} do
      view = mount_section(scope: scope(["settings", "templates_editor"]))
      select(view, "shop_offer")

      refute has_element?(view, "#templates-editor-parts")
      refute has_element?(view, "#templates-editor-create")
      assert has_element?(view, "#templates-editor-no-write")
      assert File.read!(Path.join([root, "shop_offer", "subject.en.txt"])) =~ "Offer"
    end

    test "a permission taken away while the page is open refuses the next save",
         %{root: root} do
      view = mount_section(scope: writer())
      select(view, "shop_offer")

      send(view.pid, {:scope, scope(["settings", "templates_editor"])})
      _ = render(view)

      assert save(view, %{subject: "Sneaky"}) =~ "You are not allowed to change templates"
      assert File.read!(Path.join([root, "shop_offer", "subject.en.txt"])) =~ "Offer"
    end

    test "the module switched off while the page is open refuses the next save",
         %{root: root} do
      view = mount_section(scope: writer())
      select(view, "shop_offer")

      {:ok, _} = PhoenixKitTemplatesEditor.disable_system()

      assert save(view, %{subject: "Sneaky"}) =~ "You are not allowed to change templates"
      assert File.read!(Path.join([root, "shop_offer", "subject.en.txt"])) =~ "Offer"
    end

    test "editable: false — nobody writes, whatever they hold", %{root: root} do
      Application.put_env(:phoenix_kit_templates_editor, :editable, false)
      view = mount_section(scope: scope(["*"]))
      select(view, "shop_offer")

      refute has_element?(view, "#templates-editor-parts")
      refute has_element?(view, "#templates-editor-no-write")
      assert has_element?(view, "#templates-editor-intro", "Read only on this server")
      assert File.exists?(Path.join([root, "shop_offer", "subject.en.txt"]))
    end
  end

  test "a new template's directory and file are left group-writable", %{root: root} do
    view = mount_section(scope: writer())

    view
    |> form("#templates-editor-create", create: %{name: "shop_new", copy_from: ""})
    |> render_submit()

    save(view, %{subject: "Fresh"})

    dir = Path.join(root, "shop_new")
    assert Bitwise.band(File.stat!(dir).mode, 0o7777) == 0o2775
    assert Bitwise.band(File.stat!(Path.join(dir, "subject.en.txt")).mode, 0o7777) == 0o664
  end

  describe "changed and not committed" do
    setup %{repo: repo} do
      File.write!(Path.join(repo, "README"), "repo")
      git!(repo, ["init", "-q"])
      git!(repo, ["add", "."])
      git!(repo, ["commit", "-q", "--no-verify", "-m", "init"])
      :ok
    end

    test "not asked of git on opening the tab; a button asks", %{root: root} do
      File.write!(Path.join([root, "shop_offer", "text.en.txt"]), "Changed by hand")
      view = mount_section(scope: writer())

      refute has_element?(view, "#templates-editor-uncommitted")

      view |> element("#templates-editor-uncommitted-check") |> render_click()

      assert has_element?(
               view,
               "#templates-editor-uncommitted li",
               "priv/templates/shop_offer/text.en.txt"
             )
    end

    test "listed again after every change the editor makes" do
      view = mount_section(scope: writer())
      select(view, "shop_offer")
      save(view, %{subject: "New offer"})

      assert has_element?(
               view,
               "#templates-editor-uncommitted li",
               "priv/templates/shop_offer/subject.en.txt"
             )
    end

    test "a committed tree says so" do
      view = mount_section(scope: writer())
      view |> element("#templates-editor-uncommitted-check") |> render_click()

      assert has_element?(view, "#templates-editor-uncommitted-none")
    end
  end

  test "the module's own preview: the email in its group's chrome, the samples filled in" do
    view = mount_section(scope: writer())
    select(view, "shop_offer")

    srcdoc =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#templates-editor-preview iframe")
      |> LazyHTML.attribute("srcdoc")
      |> List.first()

    assert srcdoc =~ "SHOP-HEADER"
    assert srcdoc =~ "Hello, Mari!"
    assert has_element?(view, "#templates-editor-preview-subject", "Offer 37")
  end

  test "the layout's variables, less the branding's, are named in the hints" do
    view = mount_section(scope: writer())

    hint = view |> element("#templates-editor-layout-variables") |> render()
    assert hint =~ "{{site_name}}"
    assert hint =~ "{{site_url}}"
    refute hint =~ "{{logo_url}}"
    refute hint =~ "{{accent_color}}"
  end
end
