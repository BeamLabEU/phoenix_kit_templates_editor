defmodule PhoenixKitTemplatesEditor.Integration.SectionTest do
  # The tab with the module enabled: who may write (the config's `editable`
  # and the `templates_editor.write` permission, asked again on every
  # change), what a write leaves on disk, the list of what is not committed,
  # and the module's own preview.
  use PhoenixKitTemplatesEditor.DataCase, async: false

  import Phoenix.LiveViewTest
  import PhoenixKitTemplatesEditor.SectionCase

  alias PhoenixKit.Templates
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

  # What Leaf tells the editor when the writer has typed `markdown`.
  defp edit_body(view, markdown) do
    [doc] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#templates-editor-body [phx-hook='Leaf']")
      |> Enum.flat_map(&LazyHTML.attribute(&1, "id"))

    message =
      {:leaf_changed, %{editor_id: doc, markdown: markdown, html: "", dirty: true}}

    Phoenix.LiveView.send_update(view.pid, PhoenixKitTemplatesEditor.Web.Editor,
      id: "templates-editor",
      leaf: message
    )

    render(view)
  end

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
      refute has_element?(view, "#templates-editor-hints")
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

      # The page's new scope reaches the editor at once: no form any more ...
      refute has_element?(view, "#templates-editor-parts")

      # ... and a forged save is refused on the server all the same.
      html =
        render_click(with_target(view, "#templates-editor"), "save", %{
          "parts" => %{"subject" => "Sneaky"}
        })

      assert html =~ "read-only here"
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
      refute has_element?(view, "#templates-editor-intro")
      assert File.exists?(Path.join([root, "shop_offer", "subject.en.txt"]))
    end
  end

  describe "layouts through the tab" do
    test "a writer sets an email's layout and makes a new one; without the permission, refused",
         %{root: root} do
      view = mount_section(scope: writer())
      select(view, "shop_offer")

      view
      |> form("#templates-editor-layouts-create",
        layout_create: %{name: "shop-partner", copy_from: "shop"}
      )
      |> render_submit()

      assert File.read!(Path.join([root, "_header-shop-partner", "html.html"])) =~ "SHOP-HEADER"

      view
      |> form("#templates-editor-email-layout", email_layout: %{group: "shop-partner"})
      |> render_change()

      assert File.read!(Path.join([root, "shop_offer", "layout.txt"])) == "shop-partner"

      send(view.pid, {:scope, scope(["settings", "templates_editor"])})
      _ = render(view)

      refute has_element?(view, "#templates-editor-email-layout")

      html =
        render_click(with_target(view, "#templates-editor"), "set_layout", %{
          "email_layout" => %{"group" => ""}
        })

      assert html =~ "read-only here"
      assert File.read!(Path.join([root, "shop_offer", "layout.txt"])) == "shop-partner"
    end
  end

  # The README's setup, not the module: a setgid root passes its group on,
  # and the module changes no mode after the write.
  test "a new template's directory takes the root's setgid bit", %{root: root} do
    File.chmod!(root, 0o2775)
    view = mount_section(scope: writer())

    view
    |> form("#templates-editor-create", create: %{name: "shop_new", copy_from: ""})
    |> render_submit()

    save(view, %{subject: "Fresh"})

    dir = Path.join(root, "shop_new")
    assert Bitwise.band(File.stat!(dir).mode, 0o2000) == 0o2000
    assert File.read!(Path.join(dir, "subject.en.txt")) == "Fresh"
  end

  # Core reads the root by a path string of its own (a link under `_build`,
  # say); the library's cache is keyed on it, so a change must drop that
  # path's entries too — after a save and after a deletion alike.
  test "a change is read at once through core's own path to the root",
       %{root: root, tmp_dir: tmp} do
    core = Path.join(tmp, "core_link")
    File.ln_s!(root, core)
    previous = Application.fetch_env(:phoenix_kit, :template_paths)
    Application.put_env(:phoenix_kit, :template_paths, [core])

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:phoenix_kit, :template_paths, value)
        :error -> Application.delete_env(:phoenix_kit, :template_paths)
      end

      Overrides.reset_cache([core])
    end)

    text = fn -> Templates.render("shop_offer", %{}, %{}, locale: "en", paths: [core]).text end
    assert text.() == "Hello, {{customer_name}}!"

    view = mount_section(scope: writer())
    select(view, "shop_offer")
    edit_body(view, "Saved")
    save(view, %{})
    assert text.() == "Saved"

    edit_body(view, "")
    save(view, %{})
    assert text.() in [nil, ""]
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

  describe "the actions menu" do
    test "a writer: one «⋯» menu at the top of the list holds Reload and the git check" do
      view = mount_section(scope: writer())

      assert has_element?(view, "#templates-editor-actions")
      assert has_element?(view, "#templates-editor-actions #templates-editor-reload")
      assert has_element?(view, "#templates-editor-actions #templates-editor-uncommitted-check")
      assert has_element?(view, "#templates-editor-list #templates-editor-actions")
      # the editor's own Reload button is not drawn beside the menu
      refute has_element?(view, "#templates-editor-list > #templates-editor-reload")
    end

    test "Reload from the menu reads the files again", %{root: root} do
      view = mount_section(scope: writer())
      select(view, "shop_offer")

      File.write!(Path.join([root, "shop_offer", "subject.en.txt"]), "Changed by hand")
      Overrides.reset_cache([root])

      html = view |> element("#templates-editor-reload") |> render_click()

      assert html =~ "Read again from disk."

      assert has_element?(
               view,
               "#templates-editor-parts input[name='parts[subject]'][value='Changed by hand']"
             )
    end

    test "a reader has no menu, and a forged reload changes nothing" do
      view = mount_section(scope: scope(["settings", "templates_editor"]))

      refute has_element?(view, "#templates-editor-actions")
      refute has_element?(view, "#templates-editor-reload")

      html = render_click(with_target(view, "#templates-editor"), "reload", %{})
      refute html =~ "Read again from disk."
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
end
