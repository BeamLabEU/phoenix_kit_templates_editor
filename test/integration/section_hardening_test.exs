defmodule PhoenixKitTemplatesEditor.Integration.SectionHardeningTest do
  # Round 1 of the final and security reviews: asking git what is not
  # committed is a writer's action, and not more often than once in a few
  # seconds; an event the section does not know changes
  # nothing; the scope hook keeps no scope in the process of a page's first,
  # disconnected render (the HTTP connection's, reused across requests).
  use PhoenixKitTemplatesEditor.DataCase, async: false

  import Phoenix.LiveViewTest
  import PhoenixKitTemplatesEditor.SectionCase

  alias Phoenix.LiveView.Controller
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Test.Endpoint
  alias PhoenixKitTemplatesEditor.Test.SectionHost
  alias PhoenixKitTemplatesEditor.Web.ScopeHook

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    repo = Path.join(tmp, "repo")
    root = Path.join(repo, "priv/templates")
    on_exit(fn -> Overrides.reset_cache([root]) end)

    put(root, "shop_offer", "subject.en.txt", "Offer")
    put(root, "shop_offer", "text.en.txt", "Hello")
    File.write!(Path.join(repo, "README"), "repo")
    git!(repo, ["init", "-q"])
    git!(repo, ["add", "."])
    git!(repo, ["commit", "-q", "--no-verify", "-m", "init"])

    configure(root: root, editable: true, name_prefixes: ["shop_"], locales: ["en"])
    {:ok, _} = PhoenixKitTemplatesEditor.enable_system()
    %{root: root}
  end

  defp git!(repo, args) do
    identity = ["-c", "user.name=Test", "-c", "user.email=test@example.com"]
    {_out, 0} = System.cmd("git", identity ++ ["-c", "commit.gpgsign=false" | args], cd: repo)
  end

  defp reader, do: scope(["settings", "templates_editor"])

  describe "what is not committed" do
    test "a reader is not offered it, and a forged click asks nothing", %{root: root} do
      File.write!(Path.join([root, "shop_offer", "text.en.txt"]), "Changed")
      view = mount_section(scope: reader())

      refute has_element?(view, "#templates-editor-uncommitted-check")

      render_click(with_target(view, "#templates-editor-section"), "check_uncommitted", %{})

      refute has_element?(view, "#templates-editor-uncommitted")
      refute has_element?(view, "#templates-editor-uncommitted-none")
    end

    test "asked once in a few seconds", %{root: root} do
      view = mount_section(scope: writer())
      view |> element("#templates-editor-uncommitted-check") |> render_click()
      assert has_element?(view, "#templates-editor-uncommitted-none")

      File.write!(Path.join([root, "shop_offer", "text.en.txt"]), "Changed")
      view |> element("#templates-editor-uncommitted-check") |> render_click()

      assert has_element?(view, "#templates-editor-uncommitted-none")
    end
  end

  test "an event the section does not know changes nothing" do
    view = mount_section(scope: writer())

    render_click(with_target(view, "#templates-editor-section"), "no_such_event", %{})

    assert Process.alive?(view.pid)
    assert has_element?(view, "#templates-editor-intro")
  end

  describe "the first, disconnected render" do
    test "leaves no scope behind in its process" do
      _view = mount_section(scope: writer())

      assert ScopeHook.current_scope() == nil
    end

    test "shows the files read only for the moment, without a missing-hook notice" do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Plug.Conn.put_private(:phoenix_endpoint, Endpoint)

      html =
        conn
        |> Controller.live_render(SectionHost, session: %{"scope" => writer(), "locale" => nil})
        |> Map.fetch!(:resp_body)

      assert html =~ "templates-editor-intro"
      refute html =~ "templates-editor-no-write"
      assert ScopeHook.current_scope() == nil
    end
  end
end
