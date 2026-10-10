defmodule PhoenixKitTemplatesEditor.Integration.SectionModuleEmailsTest do
  # The tab with core's own catalogue: core's emails listed read only, none
  # given a file until the host says `overridable`, one given a file from its
  # built-in text by a writer with `overridable: :all`, the sign-in emails
  # kept out of `:all`, "Send to me" through the host's callback to the user
  # of the page.
  use PhoenixKitTemplatesEditor.DataCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest
  import PhoenixKitTemplatesEditor.SectionCase

  alias PhoenixKit.Activity.Entry
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKit.Users.Auth.User

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp} do
    root = Path.join(tmp, "templates")
    on_exit(fn -> Overrides.reset_cache([root]) end)
    put(root, "shop_offer", "subject.en.txt", "Offer")
    test_pid = self()

    configure(
      root: root,
      editable: true,
      name_prefixes: ["shop_"],
      locales: ["en"],
      test_send: fn name, locale, user ->
        send(test_pid, {:test_send, name, locale, user.email})
        :ok
      end
    )

    {:ok, _} = PhoenixKitTemplatesEditor.enable_system()
    %{root: root}
  end

  defp open_module(view, name) do
    view
    |> element(
      "#templates-editor-module-emails [phx-click=select_module][phx-value-name=#{name}]"
    )
    |> render_click()
  end

  defp overridable(value),
    do: Application.put_env(:phoenix_kit_templates_editor, :overridable, value)

  test "by default no email core sends is overridable: listed, read only", %{root: root} do
    view = mount_section(scope: writer())
    open_module(view, "welcome")

    assert has_element?(view, "#templates-editor-module-email-not-overridable")
    refute has_element?(view, "#templates-editor-module-create-default")
    refute File.exists?(Path.join(root, "welcome"))
  end

  test "core's emails, read only until a writer gives one a file", %{root: root} do
    overridable(:all)
    view = mount_section(scope: writer())
    list = view |> element("#templates-editor-module-emails") |> render()
    assert list =~ "welcome"
    assert list =~ "reset_password"

    open_module(view, "welcome")
    assert has_element?(view, "#templates-editor-module-email-sources", "built-in text")

    view |> element("#templates-editor-module-create-default") |> render_click()

    assert File.exists?(Path.join([root, "welcome", "subject.en.txt"]))
    assert has_element?(view, "#templates-editor-parts")

    assert [%{action: "templates_editor.created_from_default", metadata: metadata}] =
             Repo.all(from(e in Entry, where: e.module == "templates_editor"))

    assert metadata == %{"template" => "welcome"}
  end

  test "the sign-in emails are not overridable by :all, and warned about", %{root: root} do
    overridable(:all)
    view = mount_section(scope: writer())
    open_module(view, "reset_password")

    assert has_element?(view, "#templates-editor-auth-warning")
    assert has_element?(view, "#templates-editor-module-email-not-overridable")
    refute has_element?(view, "#templates-editor-module-create-default")
    refute File.exists?(Path.join(root, "reset_password"))
  end

  test "Send to me: the host's callback, to the user of the page" do
    user = %User{
      uuid: UUIDv7.generate(),
      email: "me-#{System.unique_integer([:positive])}@example.com"
    }

    scope = %{writer() | user: user}
    view = mount_section(scope: scope)

    view |> element("#templates-editor button[phx-value-name=shop_offer]") |> render_click()
    html = view |> element("#templates-editor-test-send") |> render_click()

    assert_received {:test_send, "shop_offer", "en", email}
    assert email == user.email
    assert html =~ "Sent to #{user.email}."
  end
end
