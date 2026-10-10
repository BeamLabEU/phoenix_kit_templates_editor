defmodule PhoenixKitTemplatesEditor.NamesTest do
  # Which names an editor may show and write (spec §4.10 Б11): the shared
  # header, footer and layout only where the host allows them, a layout's
  # parts by the exact namespace of its group, the emails core and other
  # modules send never — whatever the name prefixes say.
  use ExUnit.Case, async: true

  alias PhoenixKitTemplatesEditor.Names

  defp rules(overrides \\ %{}) do
    Map.merge(
      %{
        prefixes: ["shop_"],
        layout_groups: ["shop"],
        shared_layout_editable: false,
        reserved: []
      },
      Map.new(overrides)
    )
  end

  describe "chrome/1" do
    test "a layout part of a group, a shared part, anything else" do
      assert Names.chrome("_header-shop") == {:header, "shop"}
      assert Names.chrome("_footer-shop-supplier") == {:footer, "shop-supplier"}
      assert Names.chrome("_layout-x") == {:layout, "x"}
      assert Names.chrome("_header") == {:header, nil}
      assert Names.chrome("_layout") == {:layout, nil}

      for name <- [
            "_headerx",
            "_header_shop",
            "_header-Shop",
            "header-shop",
            "_header-",
            "x",
            nil
          ] do
        assert Names.chrome(name) == nil, "#{inspect(name)} is not a layout part"
      end
    end

    test "part_name/2 builds the name back" do
      assert Names.part_name(:footer, "shop") == "_footer-shop"
      assert Names.part_name(:header, nil) == "_header"
    end
  end

  describe "in_namespace?/2" do
    test "the group itself and its dash-children, not a longer word" do
      assert Names.in_namespace?("andi", "andi")
      assert Names.in_namespace?("andi-supplier", "andi")
      refute Names.in_namespace?("andix", "andi")
      refute Names.in_namespace?("and", "andi")
    end
  end

  describe "check/2" do
    test "an email under a prefix" do
      assert Names.check("shop_offer", rules()) == :ok
      assert Names.check("other_offer", rules()) == {:error, :prefix}
    end

    test "a layout part in a group of layout_groups' namespace" do
      for name <- ["_header-shop", "_footer-shop-supplier", "_layout-shop"] do
        assert Names.check(name, rules()) == :ok, name
      end

      assert Names.check("_header-shopx", rules()) == {:error, :namespace}
      assert Names.check("_header-other", rules()) == {:error, :namespace}
    end

    test "a prefix shaped like a layout part is a namespace for that part, not a string prefix" do
      rules = rules(prefixes: ["shop_", "_header-andi"], layout_groups: [])

      assert Names.check("_header-andi", rules) == :ok
      assert Names.check("_header-andi-supplier", rules) == :ok
      assert Names.check("_header-andix", rules) == {:error, :namespace}
      assert Names.check("_footer-andi", rules) == {:error, :namespace}
    end

    test "a plain prefix never reaches a layout part" do
      rules = rules(prefixes: ["_", "_head"], layout_groups: [])

      assert Names.check("_header-shop", rules) == {:error, :namespace}
      assert Names.check("_headline", rules) == :ok
    end

    test "the shared parts only with shared_layout_editable: true, whatever the prefixes" do
      rules = rules(prefixes: ["_", "_header", "_layout"])

      for name <- ["_header", "_footer", "_layout"] do
        assert Names.check(name, rules) == {:error, :shared}, name
        assert Names.check(name, %{rules | shared_layout_editable: true}) == :ok, name
      end
    end

    test "a reserved name is refused whatever the prefixes" do
      rules = rules(prefixes: ["reset_"], reserved: ["reset_password"])

      assert Names.check("reset_password", rules) == {:error, :reserved}
      assert Names.check("reset_other", rules) == :ok
    end

    test "anything but a string" do
      assert Names.check(nil, rules()) == {:error, :prefix}
    end
  end

  describe "group_allowed?/2 and namespaces/1" do
    test "a group any part of which the rules allow" do
      assert Names.group_allowed?("shop-x", rules())
      refute Names.group_allowed?("shopx", rules())

      only_footer = rules(prefixes: ["_footer-andi"], layout_groups: [])
      assert Names.group_allowed?("andi-x", only_footer)
      refute Names.group_allowed?("x", only_footer)
      refute Names.group_allowed?("Bad Name", rules())
    end

    test "the namespaces, for messages" do
      assert Names.namespaces(rules(prefixes: ["_header-andi", "shop_"])) == ["shop", "andi"]
    end
  end

  describe "reserved_names/0" do
    test "core's emails, not this module's own" do
      names = Names.reserved_names()

      assert "reset_password" in names
      assert "magic_link" in names
      refute Enum.any?(names, &String.starts_with?(&1, "_"))
    end

    # Fail closed: a catalogue that cannot be read takes no sign-in email
    # out of the reserved names.
    test "the sign-in emails stay reserved when core's catalogue fails" do
      names = Names.reserved_names(fn -> raise "catalogue down" end)

      assert Names.auth_emails() -- names == []
    end
  end
end
