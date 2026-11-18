defmodule PhoenixKitTemplatesEditor.Web.ScopeHookTest do
  # The hook is no longer what the page depends on; it stays a module a host's
  # config may still name, and what it does is unchanged: it keeps the page's
  # scope only in a connected LiveView's process.
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias PhoenixKit.Users.Auth.Scope
  alias PhoenixKitTemplatesEditor.Web.ScopeHook

  setup do
    Process.delete({ScopeHook, :current_scope})
    :ok
  end

  defp socket(connected?, scope) do
    %Socket{
      transport_pid: if(connected?, do: self()),
      private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}},
      assigns: %{__changed__: %{}, phoenix_kit_current_scope: scope}
    }
  end

  test "a connected socket: the scope is kept, and read back" do
    scope = %Scope{cached_permissions: MapSet.new(["settings"])}

    assert {:cont, _socket} = ScopeHook.on_mount(:default, %{}, %{}, socket(true, scope))
    assert ScopeHook.current_scope() == scope
  end

  test "a disconnected render keeps nothing and removes what an earlier request left" do
    scope = %Scope{cached_permissions: MapSet.new(["settings"])}
    Process.put({ScopeHook, :current_scope}, scope)

    assert {:cont, _socket} = ScopeHook.on_mount(:default, %{}, %{}, socket(false, scope))
    assert ScopeHook.current_scope() == nil
  end

  test "no hook, no scope" do
    assert ScopeHook.current_scope() == nil
  end
end
