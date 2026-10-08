defmodule PhoenixKitTemplatesEditor.Test.SectionHost do
  @moduledoc false
  # A stand-in for core's email settings page: it puts the session's scope
  # on the socket the way core's auth hook does, runs the module's scope
  # hook, and mounts the section with nothing but its id — as core does.
  # `{:scope, scope}` swaps the scope, as core's scope refresh does.
  use Phoenix.LiveView

  on_mount({__MODULE__, :scope})
  on_mount(PhoenixKitTemplatesEditor.Web.ScopeHook)

  def on_mount(:scope, _params, session, socket) do
    if locale = session["locale"] do
      Gettext.put_locale(locale)
      Gettext.put_locale(PhoenixKitTemplatesEditor.Gettext, locale)
    end

    {:cont, assign(socket, :phoenix_kit_current_scope, session["scope"])}
  end

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_info({:scope, scope}, socket),
    do: {:noreply, assign(socket, :phoenix_kit_current_scope, scope)}

  @impl true
  def render(assigns) do
    ~H"""
    <div data-scope={
      inspect(@phoenix_kit_current_scope && @phoenix_kit_current_scope.cached_permissions)
    }>
      <.live_component module={PhoenixKitTemplatesEditor.Web.Section} id={:templates_editor} />
    </div>
    """
  end
end
