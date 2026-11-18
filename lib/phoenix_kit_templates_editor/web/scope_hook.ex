defmodule PhoenixKitTemplatesEditor.Web.ScopeHook do
  @moduledoc """
  Keeps the page's current scope where a component of the page, which core
  mounts with no assigns, can read it (`current_scope/0`).

  **The Email templates page no longer needs it.** It is a LiveView of its
  own (`PhoenixKitTemplatesEditor.Web.SettingsLive`) and hands its scope to
  the editor as an assign. The module stays because a host's config names it:

      # config/config.exs of a host that still lists it
      config :phoenix_kit,
        extra_live_session_on_mount: [PhoenixKitTemplatesEditor.Web.ScopeHook]

  It does nothing the editor depends on, and the line can be dropped from the
  host's config.

  The hook reads nothing but the scope core put on the socket and changes
  nothing on it. Only a connected LiveView's process keeps the scope: a
  page's first, disconnected render runs in the HTTP connection's process,
  which serves the connection's next requests too, so there the hook removes
  whatever an earlier request left and keeps nothing.
  """

  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias PhoenixKit.Users.Auth.Scope

  @key {__MODULE__, :current_scope}

  @doc false
  def on_mount(_name, _params, _session, socket) do
    if connected?(socket) do
      socket = remember(socket)
      socket = attach_hook(socket, __MODULE__, :after_render, &remember/1)

      socket =
        if socket.router,
          do: attach_hook(socket, __MODULE__, :handle_params, &remember_params/3),
          else: socket

      {:cont, socket}
    else
      Process.delete(@key)
      {:cont, socket}
    end
  end

  @doc """
  The scope of the page this process renders, as the hook last saw it;
  `nil` without the hook, or before the page has one.
  """
  @spec current_scope() :: Scope.t() | nil
  def current_scope do
    case Process.get(@key) do
      %Scope{} = scope -> scope
      _none -> nil
    end
  end

  defp remember_params(_params, _uri, socket), do: {:cont, remember(socket)}

  defp remember(socket) do
    Process.put(@key, socket.assigns[:phoenix_kit_current_scope])
    socket
  end
end
