defmodule PhoenixKitTemplatesEditor.NamesOverrideTest do
  # The explicit override of an email core or another module sends (spec
  # §4.11 П2, §4.10 Б11/Б15): `overridable` lets a reserved name in — by
  # default every one but the sign-in emails — and a module's own layout
  # group (`layout: "billing"` in its catalogue entry) the same way.
  use ExUnit.Case, async: true

  alias PhoenixKit.Email.CoreTemplates
  alias PhoenixKitTemplatesEditor.Names

  defp rules(overrides) do
    Map.merge(
      %{
        prefixes: ["shop_"],
        layout_groups: ["shop"],
        shared_layout_editable: false,
        reserved: ["reset_password", "billing_invoice", "register"]
      },
      Map.new(overrides)
    )
  end

  describe "auth_emails/0" do
    test "core's sign-in emails, by the names core sends them under" do
      assert Names.auth_emails() ==
               ~w(register reset_password update_email magic_link magic_link_registration)

      core = for %{name: name} <- CoreTemplates.entries(), do: name
      assert Names.auth_emails() -- core == []
    end
  end

  describe "overridable?/2" do
    test ":all is every name but the sign-in emails" do
      assert Names.overridable?("billing_invoice", :all)
      assert Names.overridable?("new_login_alert", :all)
      refute Names.overridable?("reset_password", :all)
      refute Names.overridable?("magic_link", :all)
    end

    test "a list is exactly its names, a sign-in email included when named" do
      assert Names.overridable?("reset_password", ["reset_password"])
      refute Names.overridable?("billing_invoice", ["reset_password"])
      refute Names.overridable?("billing_invoice", [])
      refute Names.overridable?("x", nil)
    end
  end

  describe "check/2 with overridable" do
    test "a reserved name is allowed when overridable, refused otherwise" do
      assert Names.check("billing_invoice", rules(overridable: :all)) == :ok
      assert Names.check("reset_password", rules(overridable: :all)) == {:error, :reserved}
      assert Names.check("reset_password", rules(overridable: ["reset_password"])) == :ok
      assert Names.check("billing_invoice", rules(overridable: [])) == {:error, :reserved}
    end

    test "rules without the key override nothing" do
      assert Names.check("billing_invoice", rules(%{})) == {:error, :reserved}
    end

    test "a module's layout group: its parts when overridable, never its shared look-alikes" do
      rules = rules(module_groups: ["billing"], overridable: :all)

      assert Names.check("_header-billing", rules) == :ok
      assert Names.check("_layout-billing", rules) == :ok
      assert Names.check("_header-billingx", rules) == {:error, :namespace}
      assert Names.check("_header-billing-x", rules) == {:error, :namespace}

      assert Names.check("_header-billing", %{rules | overridable: ["_footer-billing"]}) ==
               {:error, :namespace}

      assert Names.check("_footer-billing", %{rules | overridable: ["_footer-billing"]}) == :ok
    end

    test "without module groups a layout part keeps to the host's namespaces" do
      assert Names.check("_header-billing", rules(overridable: :all)) == {:error, :namespace}
    end
  end

  describe "module_groups/1" do
    test "the layout groups catalogue entries name, valid and distinct, in order" do
      entries = [
        %{name: "billing_invoice", layout: "billing"},
        %{name: "billing_receipt", layout: "billing"},
        %{name: "plain", layout: true},
        %{name: "none"},
        %{name: "bad", layout: "Not Valid"},
        %{name: "crm", layout: "crm"}
      ]

      assert Names.module_groups(entries) == ["billing", "crm"]
    end
  end
end
