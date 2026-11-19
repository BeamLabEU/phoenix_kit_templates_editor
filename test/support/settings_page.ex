defmodule PhoenixKitTemplatesEditor.Test.SettingsPage do
  @moduledoc false
  # `PhoenixKitTemplatesEditor.Web.SettingsLive` the way core mounts it: the
  # session's scope is put on the socket as `:phoenix_kit_current_scope` (core's
  # auth hook does that), then the page's own mount, render and messages run.
  # `{:scope, scope}` swaps the scope, as core's scope refresh does. It stands
  # in for the router, which a test has none of.
  use Phoenix.LiveView

  alias PhoenixKitTemplatesEditor.Web.SettingsLive

  on_mount({__MODULE__, :scope})

  def on_mount(:scope, _params, session, socket) do
    if locale = session["locale"] do
      Gettext.put_locale(locale)
      Gettext.put_locale(PhoenixKitTemplatesEditor.Gettext, locale)
    end

    {:cont, assign(socket, :phoenix_kit_current_scope, session["scope"])}
  end

  @impl true
  defdelegate mount(params, session, socket), to: SettingsLive

  @impl true
  defdelegate render(assigns), to: SettingsLive

  @impl true
  def handle_info({:scope, scope}, socket),
    do: {:noreply, assign(socket, :phoenix_kit_current_scope, scope)}

  # What core assigns when a module is switched on or off: the page renders
  # again, the scope stays as it was.
  def handle_info({:modules_version, version}, socket),
    do: {:noreply, assign(socket, :phoenix_kit_modules_version, version)}
end
