defmodule PhoenixKitTemplatesEditor.Integration.CatalogTest do
  # The host's emails reach core's "Preview emails" through the module's
  # `email_templates/0` only while the module is enabled and the host says
  # `catalog: true` — and core renders them from the same files.
  use PhoenixKitTemplatesEditor.DataCase, async: false

  alias PhoenixKit.Email.Catalog
  alias PhoenixKit.ModuleRegistry
  alias PhoenixKit.Templates.Overrides

  @moduletag :tmp_dir

  setup %{tmp_dir: root} do
    previous_env = Application.get_all_env(:phoenix_kit_templates_editor)
    previous_paths = Application.fetch_env(:phoenix_kit, :template_paths)
    Application.put_env(:phoenix_kit, :template_paths, [root])

    for {key, value} <- [
          root: root,
          name_prefixes: ["shop_", "_footer-shop"],
          locales: ["en"],
          layout_group: "shop",
          sample_variables: %{"order_number" => "37"},
          catalog: true
        ],
        do: Application.put_env(:phoenix_kit_templates_editor, key, value)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:phoenix_kit_templates_editor),
          do: Application.delete_env(:phoenix_kit_templates_editor, key)

      for {key, value} <- previous_env,
          do: Application.put_env(:phoenix_kit_templates_editor, key, value)

      case previous_paths do
        {:ok, value} -> Application.put_env(:phoenix_kit, :template_paths, value)
        :error -> Application.delete_env(:phoenix_kit, :template_paths)
      end

      Overrides.reset_cache([root])
    end)

    File.mkdir_p!(Path.join(root, "shop_offer"))
    File.write!(Path.join([root, "shop_offer", "label.en.txt"]), "Price offer")
    File.write!(Path.join([root, "shop_offer", "subject.en.txt"]), "Offer {{order_number}}")
    File.write!(Path.join([root, "shop_offer", "text.en.txt"]), "Hello")
    File.mkdir_p!(Path.join(root, "_footer-shop"))
    File.write!(Path.join([root, "_footer-shop", "html.html"]), "SHOP-FOOTER")
    :ok
  end

  test "only while the module is enabled" do
    refute Enum.any?(ModuleRegistry.all_email_templates(), &(&1.name == "shop_offer"))

    {:ok, _} = PhoenixKitTemplatesEditor.enable_system()

    assert %{label: "Price offer", module: PhoenixKitTemplatesEditor} =
             Enum.find(ModuleRegistry.all_email_templates(), &(&1.name == "shop_offer"))
  end

  test "core previews the email from the files, in the module's layout group" do
    {:ok, _} = PhoenixKitTemplatesEditor.enable_system()

    entry = Catalog.get("shop_offer")
    assert {:ok, %{content: content}} = Catalog.preview(entry, "en")

    assert content.subject == "Offer 37"
    assert content.html =~ "SHOP-FOOTER"
  end
end
