defmodule PhoenixKitTemplatesEditor.Integration.ModuleTest do
  use PhoenixKitTemplatesEditor.DataCase, async: false

  alias PhoenixKit.ModuleRegistry
  alias PhoenixKit.Users.Auth.Scope

  defp scope(keys), do: %Scope{cached_permissions: MapSet.new(keys)}

  describe "enabled?/0, enable_system/0, disable_system/0" do
    test "off by default, switched by the system calls" do
      refute PhoenixKitTemplatesEditor.enabled?()

      assert {:ok, _} = PhoenixKitTemplatesEditor.enable_system()
      assert PhoenixKitTemplatesEditor.enabled?()

      assert {:ok, _} = PhoenixKitTemplatesEditor.disable_system()
      refute PhoenixKitTemplatesEditor.enabled?()
    end

    test "the setting is stored under templates_editor_enabled for the module" do
      {:ok, _} = PhoenixKitTemplatesEditor.enable_system()

      assert PhoenixKit.Settings.get_setting("templates_editor_enabled") == "true"
    end
  end

  describe "core's registry" do
    test "discovers the module" do
      assert PhoenixKitTemplatesEditor in ModuleRegistry.all_modules()
    end

    test "collects the Settings item, and no section of the email settings page" do
      assert Enum.any?(
               ModuleRegistry.all_settings_tabs(),
               &(&1.id == :admin_settings_templates_editor)
             )

      {:ok, _} = PhoenixKitTemplatesEditor.enable_system()

      assert Enum.any?(
               ModuleRegistry.all_settings_tabs(),
               &(&1.id == :admin_settings_templates_editor)
             )

      refute Enum.any?(
               ModuleRegistry.all_email_settings_sections(),
               &(&1.id == :templates_editor)
             )
    end
  end

  describe "who is shown the Settings item" do
    alias PhoenixKit.Dashboard.Tab

    defp item do
      Enum.find(
        PhoenixKitTemplatesEditor.settings_tabs(),
        &(&1.id == :admin_settings_templates_editor)
      )
    end

    test "settings and the module key: the item; the module key alone: no item" do
      {:ok, _} = PhoenixKitTemplatesEditor.enable_system()

      assert Tab.visible?(item(), scope(["settings", "templates_editor"]))
      refute Tab.visible?(item(), scope(["templates_editor"]))
      refute Tab.visible?(item(), scope(["settings"]))
    end

    test "no scope: no item" do
      {:ok, _} = PhoenixKitTemplatesEditor.enable_system()

      refute Tab.visible?(item(), nil)
    end

    test "the module switched off: no item, even for the owner" do
      {:ok, _} = PhoenixKitTemplatesEditor.disable_system()

      refute Tab.visible?(item(), scope(["settings", "templates_editor"]))
      refute Tab.visible?(item(), scope(["*"]))
    end
  end

  describe "accessible?/1 and authorize/2" do
    setup do
      {:ok, _} = PhoenixKitTemplatesEditor.enable_system()
      :ok
    end

    test "settings and the module key let a user see the tab, not write" do
      scope = scope(["settings", "templates_editor"])

      assert PhoenixKitTemplatesEditor.accessible?(scope)
      assert PhoenixKitTemplatesEditor.authorize(scope, :read) == :ok
      assert PhoenixKitTemplatesEditor.authorize(scope, :write) == {:error, :forbidden}
    end

    test "the write sub-permission lets them write" do
      scope = scope(["settings", "templates_editor", "templates_editor.write"])

      assert PhoenixKitTemplatesEditor.authorize(scope, :write) == :ok
    end

    test "the module key alone is not enough: the page itself needs settings" do
      scope = scope(["templates_editor", "templates_editor.write"])

      refute PhoenixKitTemplatesEditor.accessible?(scope)
      assert PhoenixKitTemplatesEditor.authorize(scope, :read) == {:error, :forbidden}
      assert PhoenixKitTemplatesEditor.authorize(scope, :write) == {:error, :forbidden}
    end

    test "settings alone is not enough: the module key narrows it" do
      scope = scope(["settings"])

      refute PhoenixKitTemplatesEditor.accessible?(scope)
      assert PhoenixKitTemplatesEditor.authorize(scope, :read) == {:error, :forbidden}
    end

    test "the superadmin key grants everything" do
      scope = scope(["*"])

      assert PhoenixKitTemplatesEditor.accessible?(scope)
      assert PhoenixKitTemplatesEditor.authorize(scope, :write) == :ok
    end

    test "switching the module off takes everything away" do
      scope = scope(["*"])
      {:ok, _} = PhoenixKitTemplatesEditor.disable_system()

      refute PhoenixKitTemplatesEditor.accessible?(scope)
      assert PhoenixKitTemplatesEditor.authorize(scope, :read) == {:error, :disabled}
      assert PhoenixKitTemplatesEditor.authorize(scope, :write) == {:error, :disabled}
    end

    test "no scope, no access" do
      refute PhoenixKitTemplatesEditor.accessible?(nil)
      assert PhoenixKitTemplatesEditor.authorize(nil, :read) == {:error, :forbidden}
      assert PhoenixKitTemplatesEditor.authorize(%Scope{}, :write) == {:error, :forbidden}
    end
  end
end
