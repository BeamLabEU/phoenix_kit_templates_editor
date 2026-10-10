defmodule PhoenixKitTemplatesEditor.Web.EditorLayoutsTest do
  # Layouts in the editor: the list of a group's header, footer
  # and page layout, a new layout as a copy, deleting one no email uses, an
  # email's choice of layout (its layout.txt); the names it may touch
  # and the host's files a copy takes.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  @refused "You are not allowed to change templates"
  @read_only "These templates are read-only here"

  defp layout_seed(root) do
    seed(root)
    put(root, "_footer-shop-partner", "html.html", "<p>Partner footer</p>")
    put(root, "_header-shopx", "html.html", "<p>Not ours</p>")
    put(root, "_header", "html.html", "<p>Shared header</p>")
    put(root, "order_inquiry", "subject.et.txt", "Päring")
    put(root, "order_inquiry", "layout.txt", "shop-partner")
  end

  defp mount_layouts(root, opts \\ %{}) do
    mount_editor(root, Map.merge(%{layout_group: "shop", layout_groups: ["shop"]}, opts))
  end

  defp denying(test_pid) do
    fn action ->
      send(test_pid, {:authorize, action})
      {:error, :forbidden}
    end
  end

  defp layout_file(root, name), do: File.read(Path.join([root, name, "layout.txt"]))

  defp create_layout(view, name, copy_from) do
    view
    |> form("#editor-layouts-create", layout_create: %{name: name, copy_from: copy_from})
    |> render_submit()
  end

  defp set_layout(view, group) do
    view |> form("#editor-email-layout", email_layout: %{group: group}) |> render_change()
  end

  test "choosing a layout respects the byte limit and permits a smaller replacement",
       %{tmp_dir: root} do
    layout_seed(root)
    bytes = PhoenixKitTemplatesEditor.Files.usage(root).bytes
    view = mount_layouts(root, %{max_root_bytes: bytes})
    select(view, "order_offer")

    assert set_layout(view, "shop-partner") =~ "Not saved"
    assert layout_file(root, "order_offer") == {:error, :enoent}

    select(view, "order_inquiry")
    set_layout(view, "shop")
    assert layout_file(root, "order_inquiry") == {:ok, "shop"}
  end

  describe "the layouts list" do
    test "replaces the group of headers and footers: one entry per layout", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root)

      refute has_element?(view, "#editor-shared")
      assert has_element?(view, "#editor-layout-shop", "default")
      assert has_element?(view, "#editor-layout-shop [phx-value-name=_header-shop]")
      assert has_element?(view, "#editor-layout-shop_footer", "core")

      assert has_element?(
               view,
               "#editor-layout-shop-partner [phx-value-name=_footer-shop-partner]"
             )

      assert has_element?(view, "#editor-layout-shop-partner_header", "shared")
      assert has_element?(view, "#editor-layout-shop_emails", "order_offer")
      assert has_element?(view, "#editor-layout-shop-partner_emails", "order_inquiry")
    end

    test "a part opens in the same editor", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root)

      html =
        view
        |> element("#editor-layout-shop [phx-value-name=_header-shop]")
        |> render_click()

      assert html =~ "Subject of _header-shop"
      assert has_element?(view, "#editor-parts textarea[name='parts[html]']")
    end

    test "a group outside the namespace and the shared parts are not shown", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root)
      html = render(view)

      refute html =~ "_header-shopx"
      refute has_element?(view, "[phx-value-name=_header]")

      target = with_target(view, "#editor")
      render_click(target, "select", %{"name" => "_header"})
      render_submit(target, "save", %{"parts" => %{"html" => "<p>Hacked</p>"}})

      assert File.read!(Path.join([root, "_header", "html.html"])) == "<p>Shared header</p>"
    end

    test "the shared parts with shared_layout_editable: true", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root, %{shared_layout_editable: true})

      assert has_element?(view, "#editor-shared [phx-value-name=_header]")
      select(view, "_header")
      save(view, %{html: "<p>New shared</p>"})

      assert File.read!(Path.join([root, "_header", "html.html"])) == "<p>New shared</p>"
    end

    test "a prefix shaped like a layout part allows its namespace, not every longer name",
         %{tmp_dir: root} do
      layout_seed(root)
      view = mount_editor(root)

      assert has_element?(view, "[phx-value-name=_header-shop]")
      refute has_element?(view, "[phx-value-name=_header-shopx]")
      assert create(view, "_header-shopx") =~ "not in this editor’s layouts"
      assert create(view, "_header") =~ "shared"
      refute File.exists?(Path.join([root, "_header-shopx", "label.et.txt"]))
    end

    test "an email core or a module sends is neither shown nor created", %{tmp_dir: root} do
      seed(root)
      put(root, "order_reserved", "subject.et.txt", "Mine?")
      view = mount_editor(root, %{reserved_names: ["order_reserved"]})

      refute has_element?(view, "[phx-value-name=order_reserved]")
      assert create(view, "order_reserved") =~ "sends this email"

      view = mount_editor(root, %{name_prefixes: ["reset_", "order_"]})
      assert create(view, "reset_password") =~ "sends this email"
      refute render(view) =~ "not saved yet"
    end
  end

  describe "a new layout" do
    test "is a copy of an existing one, every part it has", %{tmp_dir: root} do
      layout_seed(root)
      put(root, "_layout-shop", "html.html", "<html>{{{content}}}</html>")
      view = mount_layouts(root)

      html = create_layout(view, "shop-new", "shop")

      assert html =~ "Created the layout “shop-new” as a copy of “shop”."

      assert File.read!(Path.join([root, "_header-shop-new", "html.html"])) ==
               "<p>Shop</p>\n"

      assert File.exists?(Path.join([root, "_layout-shop-new", "html.html"]))
      refute File.exists?(Path.join(root, "_footer-shop-new"))
      assert has_element?(view, "#editor-layout-shop-new [phx-value-name=_header-shop-new]")
      assert_received {:after_write, [_dir | _files]}
      assert_received {:after_change, "_header-shop-new"}
      assert_received {:after_change, "_layout-shop-new"}
    end

    test "refuses a bad name, a name outside the namespace and an existing layout",
         %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root)

      for {name, message} <- [
            {"Shop New", "not a valid layout name"},
            {"other", "not in this editor’s layouts"},
            {"shopx", "not in this editor’s layouts"},
            {"shop-partner", "already exists"}
          ] do
        assert create_layout(view, name, "shop") =~ message, name
      end

      refute File.exists?(Path.join(root, "_header-other"))
      refute File.exists?(Path.join(root, "_footer-shopx"))
      refute File.exists?(Path.join(root, "_header-shop-partner"))
      refute_received {:after_write, _paths}
    end

    test "only from a layout with parts of its own", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root)

      html =
        render_submit(with_target(view, "#editor"), "create_layout", %{
          "layout_create" => %{"name" => "shop-new", "copy_from" => "shopx"}
        })

      assert html =~ "There is no layout “shopx” to copy."
      refute File.exists?(Path.join(root, "_header-shop-new"))
    end

    test "read only: no form, and a forged event writes nothing", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root, %{editable: false})

      refute has_element?(view, "#editor-layouts-create")

      html =
        render_submit(with_target(view, "#editor"), "create_layout", %{
          "layout_create" => %{"name" => "shop-new", "copy_from" => "shop"}
        })

      assert html =~ @read_only
      refute File.exists?(Path.join(root, "_header-shop-new"))
    end

    test "a host's authorize that refuses: nothing is copied", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root, %{authorize: denying(self())})

      assert create_layout(view, "shop-new", "shop") =~ @refused
      assert_received {:authorize, :create}
      refute File.exists?(Path.join(root, "_header-shop-new"))
    end
  end

  describe "deleting a layout" do
    test "one an email uses is refused, naming the emails", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root)

      html = view |> element("#editor-layout-shop-partner_delete") |> render_click()

      assert html =~ "“shop-partner” is the layout of order_inquiry"
      refute has_element?(view, "#editor-layouts-delete-confirm")
      assert File.exists?(Path.join(root, "_footer-shop-partner"))

      render_click(with_target(view, "#editor"), "confirm_delete_layout", %{})
      assert File.exists?(Path.join(root, "_footer-shop-partner"))
    end

    test "one no email uses goes after a confirmation", %{tmp_dir: root} do
      layout_seed(root)
      File.rm!(Path.join([root, "order_inquiry", "layout.txt"]))
      view = mount_layouts(root)

      view |> element("#editor-layout-shop-partner_delete") |> render_click()
      assert File.exists?(Path.join(root, "_footer-shop-partner"))

      html = view |> element("#editor-layouts-delete-confirm") |> render_click()

      assert html =~ "Deleted the layout “shop-partner”."
      refute File.exists?(Path.join(root, "_footer-shop-partner"))
      refute has_element?(view, "#editor-layout-shop-partner")
      assert_received {:after_change, "_footer-shop-partner"}
    end

    test "an email that takes the layout meanwhile stops the confirmation", %{tmp_dir: root} do
      layout_seed(root)
      File.rm!(Path.join([root, "order_inquiry", "layout.txt"]))
      view = mount_layouts(root)
      view |> element("#editor-layout-shop-partner_delete") |> render_click()

      put(root, "order_inquiry", "layout.txt", "shop-partner")
      html = view |> element("#editor-layouts-delete-confirm") |> render_click()

      assert html =~ "is the layout of order_inquiry"
      assert File.exists?(Path.join(root, "_footer-shop-partner"))
    end

    test "a forged confirmation without the first step deletes nothing", %{tmp_dir: root} do
      layout_seed(root)
      File.rm!(Path.join([root, "order_inquiry", "layout.txt"]))
      view = mount_layouts(root)

      render_click(with_target(view, "#editor"), "confirm_delete_layout", %{})
      assert File.exists?(Path.join(root, "_footer-shop-partner"))
    end

    test "read only, or refused by the host: nothing goes", %{tmp_dir: root} do
      layout_seed(root)
      File.rm!(Path.join([root, "order_inquiry", "layout.txt"]))

      view = mount_layouts(root, %{editable: false})
      refute has_element?(view, "#editor-layout-shop-partner_delete")
      target = with_target(view, "#editor")

      assert render_click(target, "delete_layout", %{"group" => "shop-partner"}) =~ @read_only
      render_click(target, "confirm_delete_layout", %{})

      view = mount_layouts(root, %{authorize: denying(self())})
      html = view |> element("#editor-layout-shop-partner_delete") |> render_click()

      assert html =~ @refused
      assert_received {:authorize, :delete}
      assert File.exists?(Path.join(root, "_footer-shop-partner"))
    end
  end

  describe "an email's layout" do
    test "offers the default and every layout, the current one chosen", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root)
      select(view, "order_inquiry")

      assert has_element?(view, "#editor-email-layout option[value='']", "default (shop)")
      assert has_element?(view, "#editor-email-layout option[value=shop]")
      assert has_element?(view, "#editor-email-layout option[value=shop-partner][selected]")
    end

    test "choosing one writes layout.txt and previews in it at once", %{tmp_dir: root} do
      layout_seed(root)

      preview = fn name, _locale ->
        layout =
          case File.read(Path.join([root, name, "layout.txt"])) do
            {:ok, group} -> group
            {:error, _} -> "default"
          end

        {"S", "<p>in #{layout}</p>"}
      end

      view = mount_layouts(root, %{preview: preview})
      select(view, "order_offer")
      assert render(view) =~ "in default"

      html = set_layout(view, "shop-partner")

      assert layout_file(root, "order_offer") == {:ok, "shop-partner"}
      assert html =~ "in shop-partner"
      assert_received {:after_write, [path]}
      assert path == Path.join([root, "order_offer", "layout.txt"])
      assert_received {:after_change, "order_offer"}

      html = set_layout(view, "")

      assert layout_file(root, "order_offer") == {:error, :enoent}
      assert html =~ "in default"
    end

    test "a group outside the namespace is refused", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root)
      select(view, "order_offer")

      for group <- ["shopx", "Bad", "other"] do
        render_change(with_target(view, "#editor"), "set_layout", %{
          "email_layout" => %{"group" => group}
        })
      end

      assert layout_file(root, "order_offer") == {:error, :enoent}
    end

    test "not for a layout part or an unsaved draft", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root)

      select(view, "_header-shop")
      refute has_element?(view, "#editor-email-layout")

      render_change(with_target(view, "#editor"), "set_layout", %{
        "email_layout" => %{"group" => "shop"}
      })

      refute File.exists?(Path.join([root, "_header-shop", "layout.txt"]))

      create(view, "order_new")
      refute has_element?(view, "#editor-email-layout")
    end

    test "read only: shown, not changeable", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root, %{editable: false})
      select(view, "order_inquiry")

      refute has_element?(view, "#editor-email-layout")
      assert has_element?(view, "#editor-email-layout-current", "shop-partner")

      html =
        render_change(with_target(view, "#editor"), "set_layout", %{
          "email_layout" => %{"group" => ""}
        })

      assert html =~ @read_only
      assert layout_file(root, "order_inquiry") == {:ok, "shop-partner"}
    end

    test "a host's authorize that refuses: layout.txt stays", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root, %{authorize: denying(self())})
      select(view, "order_inquiry")

      assert set_layout(view, "") =~ @refused
      assert_received {:authorize, :save}
      assert layout_file(root, "order_inquiry") == {:ok, "shop-partner"}
    end

    test "a copy of an email takes its layout along", %{tmp_dir: root} do
      layout_seed(root)
      view = mount_layouts(root)

      create(view, "order_copy", "order_inquiry")

      assert layout_file(root, "order_copy") == {:ok, "shop-partner"}
      assert has_element?(view, "#editor-email-layout option[value=shop-partner][selected]")
    end
  end

  describe "the host's own files in a copy" do
    defp choose_source(view, name, copy_from) do
      view
      |> form("#editor-create", create: %{name: name, copy_from: copy_from})
      |> render_change()
    end

    test "are listed to choose, all taken by default", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "audience.txt", "partner\n")
      view = mount_editor(root)

      choose_source(view, "order_copy", "order_offer")

      assert has_element?(
               view,
               "#editor-create-extras input[type=checkbox][value='audience.txt'][checked]"
             )

      create(view, "order_copy", "order_offer")
      assert File.read!(Path.join([root, "order_copy", "audience.txt"])) == "partner\n"
    end

    test "one left unticked is not copied", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "audience.txt", "partner\n")
      put(root, "order_offer", "notes.md", "n")
      view = mount_editor(root)
      choose_source(view, "order_copy", "order_offer")

      view
      |> form("#editor-create",
        create: %{name: "order_copy", copy_from: "order_offer", keep: ["", "notes.md"]}
      )
      |> render_submit()

      copy = Path.join(root, "order_copy")
      refute File.exists?(Path.join(copy, "audience.txt"))
      assert File.exists?(Path.join(copy, "notes.md"))
      assert File.exists?(Path.join(copy, "text.et.txt"))
      assert_received {:after_write, paths}
      refute Path.join(copy, "audience.txt") in paths
    end

    test "a choice made for another source does not count", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "audience.txt", "partner\n")
      view = mount_editor(root)

      render_submit(with_target(view, "#editor"), "create", %{
        "create" => %{
          "name" => "order_copy",
          "copy_from" => "order_offer",
          "keep_for" => "order_other",
          "keep" => [""]
        }
      })

      assert File.exists?(Path.join([root, "order_copy", "audience.txt"]))
    end

    # The browser redraws a field it does not have focused from what the page
    # says: the form's values are drawn from the server, or the redraw that
    # brings the list in empties the name, or puts the source back to Empty.
    test "the name and the source stay as given, in whichever order", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "audience.txt", "partner\n")
      view = mount_editor(root)
      name_field = ~s(#editor-create input[name="create[name]"])
      source = ~s(#editor-create select[name="create[copy_from]"])

      choose_source(view, "order_copy", "")
      choose_source(view, "order_copy", "order_offer")

      assert has_element?(view, "#editor-create-extras")
      assert has_element?(view, ~s(#{name_field}[value="order_copy"]))
      assert has_element?(view, ~s(#{source} option[value="order_offer"][selected]))
      refute has_element?(view, ~s(#{source} option[value=""][selected]))

      choose_source(view, "order_copy_2", "order_offer")

      assert has_element?(view, ~s(#{name_field}[value="order_copy_2"]))
      assert has_element?(view, ~s(#{source} option[value="order_offer"][selected]))
    end

    test "a template made empties the form, a refused one keeps it", %{tmp_dir: root} do
      seed(root)
      put(root, "order_offer", "audience.txt", "partner\n")
      view = mount_editor(root)
      name_field = ~s(#editor-create input[name="create[name]"])
      source = ~s(#editor-create select[name="create[copy_from]"])

      choose_source(view, "Bad", "order_offer")
      assert create(view, "Bad", "order_offer") =~ "not a valid template name"
      assert has_element?(view, ~s(#{name_field}[value="Bad"]))
      assert has_element?(view, ~s(#{source} option[value="order_offer"][selected]))

      create(view, "order_copy", "order_offer")

      assert File.exists?(Path.join([root, "order_copy", "audience.txt"]))
      assert has_element?(view, ~s(#{name_field}[value=""]))
      assert has_element?(view, ~s(#{source} option[value=""][selected]))
      refute has_element?(view, "#editor-create-extras")
    end

    # The copy is on disk: what the host's callbacks say after it is told,
    # but the form is done with.
    test "a copy made empties the form even when the host's after_write fails",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{after_write: fn _paths -> raise "chown failed" end})
      name_field = ~s(#editor-create input[name="create[name]"])

      choose_source(view, "order_copy", "order_offer")

      log =
        capture_log(fn ->
          assert create(view, "order_copy", "order_offer") =~ "chown failed"
        end)

      assert log =~ "after_write"

      assert File.exists?(Path.join([root, "order_copy", "subject.et.txt"]))
      assert has_element?(view, ~s(#{name_field}[value=""]))
    end

    test "none to list, no list", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      choose_source(view, "order_copy", "order_offer")

      refute has_element?(view, "#editor-create-extras")
    end
  end
end
