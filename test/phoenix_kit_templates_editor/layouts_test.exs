defmodule PhoenixKitTemplatesEditor.LayoutsTest do
  # Layouts: a group's header, footer and page layout, each its
  # own or inherited (the shared part, else core's), and the emails using
  # the group — by their layout.txt, else the default group.
  use ExUnit.Case, async: true

  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Layouts

  @moduletag :tmp_dir

  defp put(root, name, file, content) do
    File.mkdir_p!(Path.join(root, name))
    File.write!(Path.join([root, name, file]), content)
  end

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

  defp seed(root) do
    put(root, "_header-shop", "html.html", "<p>Shop</p>")
    put(root, "_footer-shop", "html.et.html", "<p>Jalus</p>")
    put(root, "_footer-shop-partner", "html.html", "<p>Partner</p>")
    put(root, "_header-shopx", "html.html", "<p>Not ours</p>")
    put(root, "_footer", "html.html", "<p>Shared</p>")
    put(root, "shop_offer", "subject.et.txt", "Offer")
    put(root, "shop_inquiry", "subject.et.txt", "Inquiry")
    put(root, "shop_inquiry", "layout.txt", "shop-partner\n")
    put(root, "shop_odd", "layout.txt", "Not A Group")
    put(root, "other_mail", "layout.txt", "shop-partner")
  end

  defp list(root, rules \\ rules(), default \\ "shop"),
    do: Layouts.list(Overrides.list(root), root, rules, default)

  describe "email_layout/2" do
    test "a valid group from layout.txt, trimmed; nil without one or with a bad one",
         %{tmp_dir: root} do
      seed(root)
      files = fn name -> Enum.find(Overrides.list(root), &(&1.name == name)).files end

      assert Layouts.email_layout(root, files.("shop_inquiry")) == "shop-partner"
      assert Layouts.email_layout(root, files.("shop_offer")) == nil
      assert Layouts.email_layout(root, files.("shop_odd")) == nil
    end

    test "a layout.txt that is a link is not read", %{tmp_dir: root} do
      put(root, "shop_x", "subject.et.txt", "S")
      File.write!(Path.join(root, "target.txt"), "shop-partner")
      File.ln_s!(Path.join(root, "target.txt"), Path.join([root, "shop_x", "layout.txt"]))
      files = Enum.find(Overrides.list(root), &(&1.name == "shop_x")).files

      assert Layouts.email_layout(root, files) == nil
    end
  end

  describe "list/4" do
    test "the default group first, then the groups found, in the allowed namespace only",
         %{tmp_dir: root} do
      seed(root)

      assert Enum.map(list(root), & &1.group) == ["shop", "shop-partner"]
      assert [%{default?: true}, %{default?: false}] = list(root)
    end

    test "which parts are the group's own and where the others come from", %{tmp_dir: root} do
      seed(root)
      [shop, partner] = list(root)

      assert Enum.map(shop.parts, &{&1.kind, &1.name, &1.source}) == [
               {:header, "_header-shop", :own},
               {:footer, "_footer-shop", :own},
               {:layout, "_layout-shop", :core}
             ]

      assert Enum.map(partner.parts, &{&1.kind, &1.source}) == [
               header: :core,
               footer: :own,
               layout: :core
             ]

      # The shared footer is there, but the partner layout has its own.
      put(root, "_header", "html.html", "<p>Shared header</p>")
      [_shop, partner] = list(root)
      assert Enum.map(partner.parts, & &1.source) == [:shared, :own, :core]
    end

    test "the emails using a group: layout.txt, else the default; every email of the root",
         %{tmp_dir: root} do
      seed(root)
      [shop, partner] = list(root)

      assert shop.emails == ["shop_odd", "shop_offer"]
      assert partner.emails == ["other_mail", "shop_inquiry"]
    end

    test "a group an email names is listed even with no part of its own", %{tmp_dir: root} do
      put(root, "shop_offer", "layout.txt", "shop-new")

      assert [%{group: "shop", emails: []}, %{group: "shop-new", emails: ["shop_offer"]}] =
               list(root)

      put(root, "shop_offer", "layout.txt", "elsewhere")
      assert [%{group: "shop"}] = list(root)
    end

    test "no default group: only what is found", %{tmp_dir: root} do
      seed(root)
      assert Enum.map(list(root, rules(), nil), & &1.group) == ["shop", "shop-partner"]
      assert [%{default?: false} | _] = list(root, rules(), nil)
    end
  end

  describe "copy/4 and delete/3" do
    test "copies each part of one group to another", %{tmp_dir: root} do
      seed(root)

      assert {:ok, created} = Layouts.copy(root, "shop", "shop-new", [:header, :footer])
      assert Enum.map(created, &elem(&1, 0)) == ["_header-shop-new", "_footer-shop-new"]
      assert File.read!(Path.join([root, "_footer-shop-new", "html.et.html"])) == "<p>Jalus</p>"
    end

    test "a failed copy takes back what it made", %{tmp_dir: root} do
      seed(root)
      put(root, "_footer-shop-new", "html.html", "already there")

      assert {:error, :eexist} = Layouts.copy(root, "shop", "shop-new", [:header, :footer])
      refute File.exists?(Path.join(root, "_header-shop-new"))
      assert File.read!(Path.join([root, "_footer-shop-new", "html.html"])) == "already there"
    end

    test "deletes the parts of a group", %{tmp_dir: root} do
      seed(root)

      assert Layouts.delete(root, "shop", [:header, :footer]) ==
               {:ok, ["_header-shop", "_footer-shop"]}

      refute File.exists?(Path.join(root, "_header-shop"))
      refute File.exists?(Path.join(root, "_footer-shop"))
      assert File.exists?(Path.join(root, "_header-shopx"))
    end
  end
end
