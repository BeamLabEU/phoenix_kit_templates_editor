defmodule PhoenixKitTemplatesEditor.Web.SettingsLive do
  @moduledoc """
  The "Email templates" page of Settings (`/admin/settings/email-templates`,
  registered by `PhoenixKitTemplatesEditor.settings_tabs/0`).

  Core routes the page for a user holding `templates_editor`, and a route
  carries a single permission key, so the whole rule — the module on, and
  `settings` **and** `templates_editor` (`PhoenixKitTemplatesEditor.accessible?/1`)
  — is asked here: at `mount` (a visitor who fails it is sent back to the
  admin with a flash) and again at every render, which follows a scope core
  refreshes (a role taken away), the page showing a notice instead of the
  editor. Writing is checked by the editor on every change
  (`PhoenixKitTemplatesEditor.authorize/2`).

  The page's own `:phoenix_kit_current_scope` goes straight into
  `PhoenixKitTemplatesEditor.Web.Section`, which holds the host's config and
  the editor — no scope hook is needed.
  """
  use PhoenixKitWeb, :live_view
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  alias PhoenixKit.Utils.Routes
  alias PhoenixKitTemplatesEditor.Web.Section

  @impl true
  def mount(_params, _session, socket) do
    if PhoenixKitTemplatesEditor.accessible?(socket.assigns[:phoenix_kit_current_scope]) do
      {:ok,
       assign(socket,
         open: nil,
         path: nil,
         page_title: gettext("Email templates"),
         page_section: gettext("Settings"),
         page_section_path: Routes.path("/admin/settings")
       )}
    else
      {:ok,
       socket
       |> assign(open: nil, path: nil)
       |> put_flash(:error, gettext("You do not have access to the email templates."))
       |> push_navigate(to: Routes.path("/admin"), replace: true)}
    end
  end

  # The address may name the template to open (`?template=`): taken once,
  # when the page opens — the editor keeps the address after that itself, and
  # its later patches change nothing here, so nothing is drawn again.
  @impl true
  def handle_params(params, uri, socket) do
    if socket.assigns.path,
      do: {:noreply, socket},
      else: {:noreply, assign(socket, open: params["template"], path: URI.parse(uri).path)}
  end

  @impl true
  def render(assigns) do
    # `accessible` is asked on every render (the module switched off, a key
    # taken away); the scope goes to the section as the page's own, change-tracked
    # assign, so the section reloads the config and the templates only when core
    # replaces the scope.
    assigns =
      assign(assigns,
        accessible: PhoenixKitTemplatesEditor.accessible?(assigns[:phoenix_kit_current_scope])
      )

    ~H"""
    <div id="templates-editor-page" class="flex flex-col gap-4 px-4 py-6">
      <div :if={!@accessible} class="flex flex-col gap-4">
        <div id="templates-editor-no-access" role="alert" class="alert alert-error">
          {gettext("You do not have access to the email templates.")}
        </div>
      </div>

      <.live_component
        :if={@accessible}
        module={Section}
        id={:templates_editor}
        phoenix_kit_current_scope={@phoenix_kit_current_scope}
        open={@open}
        path={@path}
      />
    </div>
    """
  end
end
