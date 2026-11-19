defmodule PhoenixKitTemplatesEditor do
  @moduledoc """
  A PhoenixKit module that edits the host's email template files — the
  `phoenix_kit_templates` overrides core renders its emails from — on a page
  of its own under Settings, "Email templates"
  (`/admin/settings/email-templates`, `PhoenixKitTemplatesEditor.Web.SettingsLive`).

  The host keeps its templates (files under one root) and a
  `config :phoenix_kit_templates_editor` block (`PhoenixKitTemplatesEditor.Config`);
  the tool itself lives here, so another project gets the same page by adding
  the dependency and the config.

  ## Access

  The page is a Settings item (`settings_tabs/0`) that core routes under the
  `templates_editor` key. That key is not the whole rule, so the page checks
  `accessible?/1` itself when it mounts and on every render: the module is
  enabled and the user holds `settings` **and** `templates_editor`. Writing
  needs the sub-permission `templates_editor.write` as well
  (`authorize/2`). Owner holds every key; Admin is granted the module's keys
  by core when the module is first discovered.

  The module is off until switched on at Admin › Modules (`enabled?/0`); a
  disabled module contributes no menu item, and the page refuses a visitor.
  """

  use PhoenixKit.Module
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

  alias PhoenixKit.Dashboard.Tab
  alias PhoenixKit.Settings
  alias PhoenixKit.Users.Auth.Scope
  alias PhoenixKit.Utils.Routes
  alias PhoenixKitTemplatesEditor.Catalog
  alias PhoenixKitTemplatesEditor.Config

  # Single-sourced from mix.exs at compile time; the behaviour test asserts
  # `version/0 == Mix.Project.config()[:version]`.
  @version Mix.Project.config()[:version]

  @module_key "templates_editor"
  @enabled_key "templates_editor_enabled"
  @write_key "templates_editor.write"
  @page_path "email-templates"

  @impl PhoenixKit.Module
  def module_key, do: @module_key

  @impl PhoenixKit.Module
  def module_name, do: gettext("Templates editor")

  @impl PhoenixKit.Module
  @doc """
  Whether the module is switched on (`templates_editor_enabled`, off by
  default). Never raises: an unreachable settings store reads as `false`.
  """
  def enabled? do
    Settings.get_boolean_setting(@enabled_key, false)
  rescue
    _ -> false
  catch
    # A read against a dead pool exits rather than raises.
    :exit, _ -> false
  end

  @impl PhoenixKit.Module
  def enable_system do
    Settings.update_boolean_setting_with_module(@enabled_key, true, @module_key)
  end

  @impl PhoenixKit.Module
  def disable_system do
    Settings.update_boolean_setting_with_module(@enabled_key, false, @module_key)
  end

  @impl PhoenixKit.Module
  def version, do: @version

  @impl PhoenixKit.Module
  def permission_metadata do
    %{
      key: @module_key,
      # Raw msgids: core translates them through `gettext_backend` at render.
      label: gettext_noop("Templates editor"),
      icon: "hero-document-text",
      description: "Email template files: view them on the Email templates page of Settings",
      gettext_backend: PhoenixKitTemplatesEditor.Gettext,
      sub_permissions: [
        %{
          key: "write",
          label: gettext_noop("Edit email templates"),
          description: "Save, create and delete email template files where editing is allowed"
        }
      ]
    }
  end

  @impl PhoenixKit.Module
  def css_sources, do: [:phoenix_kit_templates_editor]

  @impl PhoenixKit.Module
  @doc """
  The editor's JS hook (`PhoenixKitTemplatesEditorInsertVariable`: a
  variable put at the cursor), a prebuilt file in `priv/static/assets`
  folded into the host's LiveSocket by core's `:phoenix_kit_js_sources`
  compiler — no inline script. Without it a variable goes at the end of the
  body instead.
  """
  def js_sources do
    [
      %{
        app: :phoenix_kit_templates_editor,
        file: "static/assets/phoenix_kit_templates_editor.js",
        global: "PhoenixKitTemplatesEditorHooks",
        # Only the admin templates page mounts it: core 3.6 keeps it out
        # of every public page's bundle and fetches it with the admin one (an
        # older core ignores both keys). Safe behind core's stub: the hook
        # takes no pushed event, and without it the button still works
        # through the server.
        scope: :admin,
        hooks: [
          "PhoenixKitTemplatesEditorInsertVariable",
          "PhoenixKitTemplatesEditorKeepFocus",
          "PhoenixKitTemplatesEditorFolds"
        ]
      }
    ]
  end

  @impl PhoenixKit.Module
  @doc """
  `PhoenixKitTemplatesEditor.Watcher`, always: it decides in its `init/1`
  whether to run (only where the files are edited or watched); and
  `PhoenixKitTemplatesEditor.Throttle`, which keeps "Send to me" to once in
  30 s per user.
  """
  def children, do: [PhoenixKitTemplatesEditor.Watcher, PhoenixKitTemplatesEditor.Throttle]

  @impl PhoenixKit.Module
  @doc """
  The "Email templates" item of Settings, opening
  `PhoenixKitTemplatesEditor.Web.SettingsLive` at `/admin/settings/email-templates`.
  Core hides the item while the module is switched off, and routes the page
  for users holding `templates_editor`; the item is shown only where
  `accessible?/1` holds (`settings` as well), and the page asks it again.
  """
  def settings_tabs do
    [
      Tab.new!(
        id: :admin_settings_templates_editor,
        label: gettext_noop("Email templates"),
        icon: "hero-document-text",
        path: @page_path,
        priority: 918,
        level: :admin,
        parent: :admin_settings,
        permission: @module_key,
        visible: &__MODULE__.accessible?/1,
        match: :exact,
        live_view: {PhoenixKitTemplatesEditor.Web.SettingsLive, :index},
        gettext_backend: PhoenixKitTemplatesEditor.Gettext
      )
    ]
  end

  @impl PhoenixKit.Module
  @doc """
  Nothing: the editor is a page of its own (`settings_tabs/0`). Core turns
  every section of the email settings page into a tab of it, and has no
  link-only entry that opens another page, so the module keeps no section
  there.
  """
  def email_settings_sections, do: []

  @impl PhoenixKit.Module
  @doc """
  The host's emails for core's "Preview emails" when its config says
  `catalog: true` (`PhoenixKitTemplatesEditor.Catalog.entries/1`); `[]`
  otherwise, and with a config that does not load. Core asks only while the
  module is enabled.
  """
  def email_templates do
    case Config.load() do
      {:ok, config} -> Catalog.entries(config)
      {:error, _messages} -> []
    end
  rescue
    _ -> []
  end

  @doc """
  The address of the page, through `PhoenixKit.Utils.Routes.path/2` (URL
  prefix, admin segment and locale applied) — for a host's own "Edit
  templates" links. `opts` go to `Routes.path/2`, e.g. `locale: "ru"`.

  Show such a link only when `accessible?/1` is true.
  """
  @spec tab_path(keyword()) :: String.t()
  def tab_path(opts \\ []) do
    Routes.path("/admin/settings/" <> @page_path, opts)
  end

  @doc """
  Whether `scope` may open the page: the module is enabled and the user holds
  both `settings` (the page's own key) and `templates_editor`.
  """
  @spec accessible?(Scope.t() | nil) :: boolean()
  def accessible?(scope), do: authorize(scope, :read) == :ok

  @doc """
  Checks `scope` for an action on the templates — to be called on every
  event, not only at mount, so a permission or the module switched off
  mid-session takes effect at once.

    * `:read` — what `accessible?/1` answers;
    * `:write` — `:read` plus the sub-permission `templates_editor.write`.

  Whether the files may be written at all is the host's `editable` config
  (`PhoenixKitTemplatesEditor.Config`), checked separately.
  """
  @spec authorize(Scope.t() | nil, :read | :write) :: :ok | {:error, :disabled | :forbidden}
  def authorize(scope, action) when action in [:read, :write] do
    cond do
      not enabled?() -> {:error, :disabled}
      not readable?(scope) -> {:error, :forbidden}
      action == :write and not Scope.can?(scope, @write_key) -> {:error, :forbidden}
      true -> :ok
    end
  end

  defp readable?(scope) do
    Scope.has_module_access?(scope, "settings") and
      Scope.has_module_access?(scope, @module_key)
  end
end
