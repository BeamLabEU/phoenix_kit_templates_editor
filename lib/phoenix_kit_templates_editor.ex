defmodule PhoenixKitTemplatesEditor do
  @moduledoc """
  A PhoenixKit module that edits the host's email template files — the
  `phoenix_kit_templates` overrides core renders its emails from — in a tab
  of Settings › Emails Transactional (`/admin/settings/email-sending`).

  The host keeps its templates (files under one root) and a
  `config :phoenix_kit_templates_editor` block (`PhoenixKitTemplatesEditor.Config`);
  the tool itself lives here, so another project gets the same tab by adding
  the dependency and the config.

  ## Access

  The tab is a section of core's email settings page, which core gates by the
  `settings` key. The section adds this module's own key, `templates_editor`,
  so it can only narrow that: a user sees the tab with `settings` **and**
  `templates_editor` while the module is enabled (`accessible?/1`). Writing
  needs the sub-permission `templates_editor.write` as well
  (`authorize/2`). Owner holds every key; Admin is granted the module's keys
  by core when the module is first discovered.

  The module is off until switched on at Admin › Modules (`enabled?/0`); a
  disabled module contributes no section, so the tab disappears with it.
  """

  use PhoenixKit.Module
  use Gettext, backend: PhoenixKitTemplatesEditor.Gettext

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
  @section_id :templates_editor

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
      description: "Email template files: view them on the email settings page",
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
  `PhoenixKitTemplatesEditor.Watcher`, always: it decides in its `init/1`
  whether to run (only where the files are edited or watched).
  """
  def children, do: [PhoenixKitTemplatesEditor.Watcher]

  @impl PhoenixKit.Module
  def email_settings_sections do
    title = gettext("Email templates")

    [
      %{
        id: @section_id,
        title: title,
        permission: @module_key,
        component: PhoenixKitTemplatesEditor.Web.Section,
        link: %{label: title}
      }
    ]
  end

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
  The address of the tab, through `PhoenixKit.Utils.Routes.path/2` (URL
  prefix, admin segment and locale applied) — for a host's own "Edit
  templates" links. `opts` go to `Routes.path/2`, e.g. `locale: "ru"`.

  Show such a link only when `accessible?/1` is true.
  """
  @spec tab_path(keyword()) :: String.t()
  def tab_path(opts \\ []) do
    Routes.path(
      "/admin/settings/email-sending?tab=" <> URI.encode_www_form("module_#{@section_id}"),
      opts
    )
  end

  @doc """
  Whether `scope` may see the tab: the module is enabled and the user holds
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
