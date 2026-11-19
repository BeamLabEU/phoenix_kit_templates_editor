defmodule PhoenixKitTemplatesEditor.Web.SettingsLiveParamsTest do
  # What the page does with its address (`?template=`): taken once, when the
  # page opens, with the page's own path for the editor's patches; a later
  # change of the address (the editor's own patch) changes nothing here.
  # `handle_params/3` is called directly: the test hosts are not mounted at a
  # router, where a patch cannot run.
  use ExUnit.Case, async: true

  alias PhoenixKitTemplatesEditor.Web.SettingsLive

  @uri "http://localhost/admin/settings/email-templates"

  defp socket(assigns),
    do: %Phoenix.LiveView.Socket{assigns: Map.merge(%{__changed__: %{}}, assigns)}

  test "the template the address names, and the page's path, are taken when the page opens" do
    {:noreply, socket} =
      SettingsLive.handle_params(
        %{"template" => "order_offer"},
        @uri <> "?template=order_offer",
        socket(%{open: nil, path: nil})
      )

    assert socket.assigns.open == "order_offer"
    assert socket.assigns.path == "/admin/settings/email-templates"
  end

  test "an address without a template opens none, and the path is still taken" do
    {:noreply, socket} = SettingsLive.handle_params(%{}, @uri, socket(%{open: nil, path: nil}))

    assert socket.assigns.open == nil
    assert socket.assigns.path == "/admin/settings/email-templates"
  end

  test "once taken, the editor's own patch of the address changes nothing" do
    opened = socket(%{open: "order_offer", path: "/admin/settings/email-templates"})

    {:noreply, socket} =
      SettingsLive.handle_params(
        %{"template" => "order_other"},
        @uri <> "?template=order_other",
        opened
      )

    assert socket == opened
  end
end
