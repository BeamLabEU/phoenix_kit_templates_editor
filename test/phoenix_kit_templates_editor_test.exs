defmodule PhoenixKitTemplatesEditorTest do
  use ExUnit.Case, async: true

  alias PhoenixKit.Dashboard.Tab
  alias PhoenixKit.Users.Auth.Scope
  alias PhoenixKit.Utils.Routes
  alias PhoenixKitTemplatesEditor.Web.SettingsLive

  # `function_exported?/3` answers false for a module that is merely not
  # loaded, so callback assertions would fail intermittently under a random
  # seed without this.
  setup_all do
    Code.ensure_loaded!(PhoenixKitTemplatesEditor)
    :ok
  end

  describe "behaviour implementation" do
    test "implements PhoenixKit.Module" do
      behaviours =
        PhoenixKitTemplatesEditor.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert PhoenixKit.Module in behaviours
    end

    test "has @phoenix_kit_module attribute for auto-discovery" do
      attrs = PhoenixKitTemplatesEditor.__info__(:attributes)
      assert Keyword.get(attrs, :phoenix_kit_module) == [true]
    end
  end

  describe "required callbacks" do
    test "module_key/0 is templates_editor" do
      assert PhoenixKitTemplatesEditor.module_key() == "templates_editor"
    end

    test "module_name/0 is the English name outside a translated locale" do
      assert PhoenixKitTemplatesEditor.module_name() == "Templates editor"
    end

    test "enabled?/0 returns false without a database instead of raising" do
      # No sandbox checkout in this process: the settings read fails, and
      # `enabled?/0` must answer false rather than crash its caller.
      assert PhoenixKitTemplatesEditor.enabled?() == false
    end

    test "enable_system/0 and disable_system/0 are exported" do
      assert function_exported?(PhoenixKitTemplatesEditor, :enable_system, 0)
      assert function_exported?(PhoenixKitTemplatesEditor, :disable_system, 0)
    end
  end

  describe "permission_metadata/0" do
    test "has the fields core requires, keyed by module_key" do
      meta = PhoenixKitTemplatesEditor.permission_metadata()

      assert %{key: key, label: label, icon: icon, description: description} = meta
      assert key == PhoenixKitTemplatesEditor.module_key()
      assert label == "Templates editor"
      assert icon == "hero-document-text"
      assert is_binary(description) and description != ""
    end

    test "names the module's Gettext backend for the permissions matrix" do
      assert PhoenixKitTemplatesEditor.permission_metadata().gettext_backend ==
               PhoenixKitTemplatesEditor.Gettext
    end

    test "declares the write sub-permission" do
      assert [%{key: "write", label: label, description: description}] =
               PhoenixKitTemplatesEditor.permission_metadata().sub_permissions

      assert is_binary(label) and label != ""
      assert is_binary(description) and description != ""
    end
  end

  describe "version/0" do
    test "matches mix.exs" do
      assert PhoenixKitTemplatesEditor.version() == Mix.Project.config()[:version]
    end
  end

  describe "css_sources/0" do
    test "returns the OTP app atom so Tailwind scans the module's templates" do
      assert PhoenixKitTemplatesEditor.css_sources() == [:phoenix_kit_templates_editor]
    end
  end

  describe "js_sources/0" do
    test "one bundle in priv/static, defining the namespaced insert hook under its global" do
      assert [%{app: :phoenix_kit_templates_editor, file: file, global: global}] =
               PhoenixKitTemplatesEditor.js_sources()

      assert global == "PhoenixKitTemplatesEditorHooks"
      bundle = File.read!(Path.join(:code.priv_dir(:phoenix_kit_templates_editor), file))
      assert bundle =~ "window.#{global}"
      assert bundle =~ "PhoenixKitTemplatesEditorInsertVariable"
    end

    # Core 3.6 keeps an admin-scoped bundle off public pages and stubs each
    # listed hook; a hook the bundle exports but the entry does not list
    # could never mount.
    test "admin-scoped, listing every hook the bundle exports" do
      assert [%{file: file, scope: :admin, hooks: hooks}] = PhoenixKitTemplatesEditor.js_sources()
      bundle = File.read!(Path.join(:code.priv_dir(:phoenix_kit_templates_editor), file))

      exported =
        ~r/window\.PhoenixKitTemplatesEditorHooks\.([A-Za-z0-9_]+)\s*=/
        |> Regex.scan(bundle, capture: :all_but_first)
        |> List.flatten()
        |> Enum.uniq()

      assert Enum.sort(hooks) == Enum.sort(exported)
    end
  end

  describe "optional callbacks" do
    test "no migrations, admin tabs or routes of its own" do
      assert PhoenixKitTemplatesEditor.migration_module() == nil
      assert PhoenixKitTemplatesEditor.admin_tabs() == []
      assert PhoenixKitTemplatesEditor.route_module() == nil
    end

    test "email_templates/0 is empty without catalog: true (the default)" do
      assert PhoenixKitTemplatesEditor.email_templates() == []
    end
  end

  describe "settings_tabs/0" do
    test "one item under Settings, gated by the module key, opening the page" do
      assert [tab] = PhoenixKitTemplatesEditor.settings_tabs()

      assert tab.id == :admin_settings_templates_editor
      assert tab.parent == :admin_settings
      assert tab.level == :admin
      assert tab.path == "email-templates"
      assert tab.label == "Email templates"
      assert tab.permission == PhoenixKitTemplatesEditor.module_key()
      assert tab.live_view == {SettingsLive, :index}
      assert tab.gettext_backend == PhoenixKitTemplatesEditor.Gettext
    end

    test "the page is a LiveView, not a component" do
      Code.ensure_loaded!(SettingsLive)

      assert function_exported?(SettingsLive, :mount, 3)
      assert function_exported?(SettingsLive, :render, 1)
      refute function_exported?(SettingsLive, :update, 2)
    end

    test "resolves to /admin/settings/email-templates" do
      [tab] = PhoenixKitTemplatesEditor.settings_tabs()

      assert Tab.resolve_path(tab, :settings).path == "/admin/settings/email-templates"
    end
  end

  describe "email_settings_sections/0" do
    test "contributes none: core would make every section a tab of the email page" do
      assert PhoenixKitTemplatesEditor.email_settings_sections() == []
    end
  end

  describe "tab_path/0" do
    test "is the page's address, through Routes" do
      assert PhoenixKitTemplatesEditor.tab_path() ==
               Routes.path("/admin/settings/email-templates")
    end

    test "passes options on to Routes, e.g. the locale" do
      assert PhoenixKitTemplatesEditor.tab_path(locale: "ru") ==
               Routes.path("/admin/settings/email-templates", locale: "ru")
    end

    test "is the path the Settings item resolves to" do
      [tab] = PhoenixKitTemplatesEditor.settings_tabs()

      assert PhoenixKitTemplatesEditor.tab_path() ==
               Routes.path(Tab.resolve_path(tab, :settings).path)
    end
  end

  describe "accessible?/1 and authorize/2 without a database" do
    # The module reads as disabled here (no settings store), so nobody gets
    # through, however many keys they hold.
    test "a disabled module denies even a full scope" do
      scope = %Scope{cached_permissions: MapSet.new(["*"])}

      refute PhoenixKitTemplatesEditor.accessible?(scope)
      assert PhoenixKitTemplatesEditor.authorize(scope, :read) == {:error, :disabled}
      assert PhoenixKitTemplatesEditor.authorize(scope, :write) == {:error, :disabled}
    end

    test "nil scope is denied" do
      refute PhoenixKitTemplatesEditor.accessible?(nil)
      assert {:error, _} = PhoenixKitTemplatesEditor.authorize(nil, :read)
    end
  end
end
