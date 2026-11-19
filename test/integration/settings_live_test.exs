defmodule PhoenixKitTemplatesEditor.Integration.SettingsLiveTest do
  # The Email templates page of Settings. Core routes it for the
  # `templates_editor` key alone, so the page asks the whole rule itself: the
  # module on, `settings` and `templates_editor` (`accessible?/1`) — at mount,
  # and again whenever core refreshes the scope; writing stays the editor's own
  # check on every event. None of it needs the scope hook.
  use PhoenixKitTemplatesEditor.DataCase, async: false

  import Phoenix.ConnTest, only: [build_conn: 0]
  import Phoenix.LiveViewTest
  import PhoenixKitTemplatesEditor.SectionCase

  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Test.SettingsPage

  @endpoint PhoenixKitTemplatesEditor.Test.Endpoint
  @moduletag :tmp_dir

  setup %{tmp_dir: root} do
    on_exit(fn -> Overrides.reset_cache([root]) end)

    put(root, "shop_offer", "label.en.txt", "Price offer")
    put(root, "shop_offer", "subject.en.txt", "Offer {{order_number}}")
    put(root, "shop_offer", "text.en.txt", "Hello")

    configure(
      root: root,
      editable: true,
      name_prefixes: ["shop_"],
      locales: ["en", "et"],
      sample_variables: %{"order_number" => "37"}
    )

    {:ok, _} = PhoenixKitTemplatesEditor.enable_system()
    %{root: root}
  end

  defp open(scope) do
    live_isolated(build_conn(), SettingsPage, session: %{"scope" => scope, "locale" => nil})
  end

  defp mount!(scope) do
    {:ok, view, _html} = open(scope)
    view
  end

  defp refused?(result) do
    match?({:error, {kind, %{to: _to}}} when kind in [:live_redirect, :redirect], result)
  end

  defp reader, do: scope(["settings", "templates_editor"])

  describe "who gets the page" do
    test "a writer: the page, the editor, its forms" do
      view = mount!(writer())

      # The admin bar names the page and leads back to Settings: the page has
      # no title and no back control of its own.
      refute has_element?(view, "#templates-editor-page header")
      refute has_element?(view, "#templates-editor-page a[href$='/admin/settings']")
      assert has_element?(view, "#templates-editor")
      assert has_element?(view, "#templates-editor-create")
      refute has_element?(view, "#templates-editor-no-access")
    end

    test "settings and the module key, no write: the page, read only" do
      view = mount!(reader())

      assert has_element?(view, "#templates-editor")
      assert has_element?(view, "#templates-editor-no-write")
      refute has_element?(view, "#templates-editor-create")

      view |> element("#templates-editor button[phx-value-name=shop_offer]") |> render_click()

      refute has_element?(view, "#templates-editor-parts")
      refute has_element?(view, "#templates-editor-delete")
    end

    test "no templates_editor key: no page, back to the admin with a notice" do
      assert refused?(open(scope(["settings"])))
      assert refused?(open(scope(["settings", "templates_editor.write"])))
    end

    test "no settings key: no page, whatever else is held" do
      assert refused?(open(scope(["templates_editor", "templates_editor.write"])))
    end

    test "no scope: no page" do
      assert refused?(open(nil))
    end

    test "the module switched off: no page, even for the owner" do
      {:ok, _} = PhoenixKitTemplatesEditor.disable_system()

      assert refused?(open(scope(["*"])))
    end

    test "the refusal says where it goes and why" do
      {:error, {_kind, %{to: to, flash: flash}}} = open(scope(["settings"]))

      assert to =~ "/admin"
      assert flash["error"] =~ "do not have access"
    end
  end

  describe "while the page is open" do
    test "a scope core refreshes without the key takes the editor away" do
      view = mount!(writer())
      assert has_element?(view, "#templates-editor")

      send(view.pid, {:scope, scope(["settings"])})
      _ = render(view)

      assert has_element?(view, "#templates-editor-no-access")
      refute has_element?(view, "#templates-editor")
    end

    test "the module switched off: core renders the page again, the editor is gone" do
      view = mount!(writer())
      assert has_element?(view, "#templates-editor")

      {:ok, _} = PhoenixKitTemplatesEditor.disable_system()
      send(view.pid, {:modules_version, 1})
      _ = render(view)

      assert has_element?(view, "#templates-editor-no-access")
      refute has_element?(view, "#templates-editor")
    end

    test "a page render that changes nothing of the scope does not read the config again",
         %{root: root} do
      view = mount!(writer())
      put(root, "other_mail", "text.en.txt", "Fresh")
      refute has_element?(view, "#templates-editor button[phx-value-name=other_mail]")

      configure(
        root: root,
        editable: true,
        name_prefixes: ["shop_", "other_"],
        locales: ["en", "et"]
      )

      Overrides.reset_cache([root])
      send(view.pid, {:modules_version, 2})
      _ = render(view)

      refute has_element?(view, "#templates-editor button[phx-value-name=other_mail]")

      # A scope core replaces is read again with everything else.
      send(
        view.pid,
        {:scope, scope(["settings", "templates_editor", "templates_editor.write", "x"])}
      )

      _ = render(view)

      assert has_element?(view, "#templates-editor button[phx-value-name=other_mail]")
    end

    test "a scope that loses only the write key turns the editor read only at once" do
      view = mount!(writer())
      view |> element("#templates-editor button[phx-value-name=shop_offer]") |> render_click()
      assert has_element?(view, "#templates-editor-parts")

      send(view.pid, {:scope, reader()})
      _ = render(view)

      assert has_element?(view, "#templates-editor")
      refute has_element?(view, "#templates-editor-parts")
      assert has_element?(view, "#templates-editor-no-write")
    end

    test "a write needs the write key on the server too, whatever the page showed",
         %{root: root} do
      view = mount!(writer())
      view |> element("#templates-editor button[phx-value-name=shop_offer]") |> render_click()

      send(view.pid, {:scope, reader()})
      _ = render(view)

      render_click(with_target(view, "#templates-editor"), "save", %{
        "parts" => %{"subject" => "Sneaky"}
      })

      assert File.read!(Path.join([root, "shop_offer", "subject.en.txt"])) =~ "Offer"
    end

    test "the module switched off mid-session: the next write is refused", %{root: root} do
      view = mount!(writer())
      view |> element("#templates-editor button[phx-value-name=shop_offer]") |> render_click()

      {:ok, _} = PhoenixKitTemplatesEditor.disable_system()

      html =
        view
        |> form("#templates-editor-parts", parts: %{subject: "Sneaky"})
        |> render_submit()

      assert html =~ "not allowed"
      assert File.read!(Path.join([root, "shop_offer", "subject.en.txt"])) =~ "Offer"
    end
  end

  describe "the page itself" do
    test "a save from the page writes the file; the page needs no scope hook", %{root: root} do
      view = mount!(writer())
      view |> element("#templates-editor button[phx-value-name=shop_offer]") |> render_click()

      view
      |> form("#templates-editor-parts", parts: %{subject: "New offer"})
      |> render_submit()

      assert File.read!(Path.join([root, "shop_offer", "subject.en.txt"])) == "New offer"
    end

    test "no introduction, hints or README block, a language switcher instead of hand-made tabs" do
      view = mount!(writer())
      view |> element("#templates-editor button[phx-value-name=shop_offer]") |> render_click()

      refute has_element?(view, "#templates-editor-intro")
      refute has_element?(view, "#templates-editor-hints")
      refute has_element?(view, "#templates-editor-readme")
      assert has_element?(view, "#templates-editor-languages [phx-click=locale]")
    end
  end
end
