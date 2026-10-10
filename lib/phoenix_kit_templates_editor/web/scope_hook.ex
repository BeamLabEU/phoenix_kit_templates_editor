defmodule PhoenixKitTemplatesEditor.Web.ScopeHook do
  @moduledoc """
  Tells the section who is acting.

  Core mounts the section as `<.live_component module={…} id={…} />` with
  no other assigns, so the component cannot see the page's
  `:phoenix_kit_current_scope` — yet every change must be checked against
  the user's permissions at the moment it is made. This `on_mount` hook,
  added to PhoenixKit's live sessions by the host, keeps the page's current
  scope where the section (running in the page's process) can read it
  (`current_scope/0`): after `handle_params` and after every render, so a
  scope core refreshes (a role taken away) counts from the next event on.

      # config/config.exs of the host
      config :phoenix_kit,
        extra_live_session_on_mount: [PhoenixKitTemplatesEditor.Web.ScopeHook]

  Without it the section has no scope and shows the templates read-only.
  The hook reads nothing but the scope core put on the socket and changes
  nothing on it.

  Only a connected LiveView's process keeps the scope. A page's first,
  disconnected render runs in the HTTP connection's process, which serves
  the connection's next requests too (keep-alive, a proxy's pooled
  connection) and runs no hook after the render: there the hook removes
  whatever an earlier request left and keeps nothing, and the section shows
  the files read only until the page connects, a moment later.
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
