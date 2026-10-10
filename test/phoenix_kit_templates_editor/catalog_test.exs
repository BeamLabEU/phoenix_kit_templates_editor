defmodule PhoenixKitTemplatesEditor.CatalogTest do
  # The host's emails for core's "Preview emails": with
  # `catalog: true`, every email under `name_prefixes` (no leading `_`),
  # labelled in PhoenixKit's language, then `base_locale`, then by name;
  # ordered by label, then name; the sample variables; the layout of
  # `layout.txt`, else `layout_group`; no defaults — the files are the text.
  #
  # Not async: it changes the application environment and core's template
  # paths, and sets PhoenixKit's Gettext locale.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Catalog
  alias PhoenixKitTemplatesEditor.Config

  @moduletag :tmp_dir

  setup %{tmp_dir: root} do
    previous_env = Application.get_all_env(:phoenix_kit_templates_editor)
    previous_paths = Application.fetch_env(:phoenix_kit, :template_paths)
    previous_locale = Gettext.get_locale(PhoenixKitWeb.Gettext)
    Application.put_env(:phoenix_kit, :template_paths, [root])

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:phoenix_kit_templates_editor),
          do: Application.delete_env(:phoenix_kit_templates_editor, key)

      for {key, value} <- previous_env,
          do: Application.put_env(:phoenix_kit_templates_editor, key, value)

      case previous_paths do
        {:ok, value} -> Application.put_env(:phoenix_kit, :template_paths, value)
        :error -> Application.delete_env(:phoenix_kit, :template_paths)
      end

      Gettext.put_locale(PhoenixKitWeb.Gettext, previous_locale)
      Overrides.reset_cache([root])
    end)

    seed(root)
    :ok
  end

  defp put(root, name, file, content) do
    File.mkdir_p!(Path.join(root, name))
    File.write!(Path.join([root, name, file]), content)
  end

  defp seed(root) do
    put(root, "shop_offer", "label.et.txt", "Pakkumine\n")
    put(root, "shop_offer", "label.ru.txt", "Предложение\n")
    put(root, "shop_offer", "subject.et.txt", "Offer")
    put(root, "shop_invoice", "label.et.txt", "Arve")
    put(root, "shop_invoice", "subject.et.txt", "Invoice")
    put(root, "shop_invoice", "layout.txt", "shop-billing\n")
    put(root, "shop_draft", "subject.ru.txt", "Draft")
    put(root, "_header-shop", "html.html", "<b>Shop</b>")
    put(root, "other_mail", "subject.et.txt", "Not ours")
  end

  defp config(root, overrides \\ []) do
    {:ok, config} =
      Config.load(
        Keyword.merge(
          [
            root: root,
            name_prefixes: ["shop_", "_header-shop"],
            locales: ["et", "ru", "en"],
            layout_group: "shop",
            layout_groups: ["shop"],
            sample_variables: %{"order_number" => "37"},
            catalog: true
          ],
          overrides
        )
      )

    config
  end

  describe "emails/2" do
    test "the emails under the prefixes, by label in the language, then by name",
         %{tmp_dir: root} do
      assert Catalog.emails(config(root), "et") == [
               %{name: "shop_invoice", label: "Arve", layout: "shop-billing"},
               %{name: "shop_offer", label: "Pakkumine", layout: "shop"},
               %{name: "shop_draft", label: "shop_draft", layout: "shop"}
             ]
    end

    test "a language without a label falls back to base_locale, then the name",
         %{tmp_dir: root} do
      assert Enum.map(Catalog.emails(config(root), "ru"), &{&1.name, &1.label}) == [
               {"shop_invoice", "Arve"},
               {"shop_draft", "shop_draft"},
               {"shop_offer", "Предложение"}
             ]
    end

    test "a layout.txt that names no valid group is the configured group", %{tmp_dir: root} do
      put(root, "shop_invoice", "layout.txt", "Not A Group")

      assert %{layout: "shop"} =
               Enum.find(Catalog.emails(config(root), "et"), &(&1.name == "shop_invoice"))
    end

    test "a linked label is not read", %{tmp_dir: root} do
      put(root, "shop_offer", "notes.txt", "SECRET")
      File.rm!(Path.join([root, "shop_offer", "label.et.txt"]))
      File.ln_s!("notes.txt", Path.join([root, "shop_offer", "label.et.txt"]))

      assert %{label: "shop_offer"} =
               Enum.find(Catalog.emails(config(root), "et"), &(&1.name == "shop_offer"))
    end
  end

  describe "entries/1" do
    test "core catalog entries, labelled in PhoenixKit's language", %{tmp_dir: root} do
      Gettext.put_locale(PhoenixKitWeb.Gettext, "ru")

      entries = Catalog.entries(config(root))

      assert Enum.map(entries, & &1.name) == ["shop_invoice", "shop_draft", "shop_offer"]
      offer = Enum.find(entries, &(&1.name == "shop_offer"))
      assert offer.label == "Предложение"
      assert offer.variables == %{"order_number" => "37"}
      assert offer.layout == "shop"
      refute Map.has_key?(offer, :defaults)
    end

    test "a callback for the sample variables is passed on as a function", %{tmp_dir: root} do
      entries = Catalog.entries(config(root, sample_variables: {__MODULE__, :samples}))

      assert [%{variables: variables} | _] = entries
      assert variables.() == samples()
    end

    test "no layout group and no layout.txt: no layout", %{tmp_dir: root} do
      config = config(root, layout_group: nil, layout_groups: nil)

      assert %{name: "shop_offer"} =
               offer = Enum.find(Catalog.entries(config), &(&1.name == "shop_offer"))

      refute Map.has_key?(offer, :layout)
    end

    test "off unless catalog: true", %{tmp_dir: root} do
      assert Catalog.entries(config(root, catalog: false)) == []
    end

    test "off, with a warning, when the root is not the directory core reads",
         %{tmp_dir: root} do
      other = Path.join(root, "elsewhere")
      File.mkdir_p!(other)
      Application.put_env(:phoenix_kit, :template_paths, [other])
      Logger.put_module_level(Catalog, :warning)
      on_exit(fn -> Logger.delete_module_level(Catalog) end)

      log = capture_log([level: :warning], fn -> assert Catalog.entries(config(root)) == [] end)

      assert log =~ "catalog"
      refute log =~ root
    end

    test "on when core reads the same directory by another path", %{tmp_dir: root} do
      link = Path.join(Path.dirname(root), "link-#{System.unique_integer([:positive])}")
      File.ln_s!(root, link)
      on_exit(fn -> File.rm(link) end)
      Application.put_env(:phoenix_kit, :template_paths, [link])

      assert Catalog.root_read_by_core?(config(root))
      assert length(Catalog.entries(config(root))) == 3
    end
  end

  describe "PhoenixKitTemplatesEditor.email_templates/0" do
    test "reads the config", %{tmp_dir: root} do
      for {key, value} <- [
            root: root,
            name_prefixes: ["shop_"],
            locales: ["et"],
            catalog: true
          ],
          do: Application.put_env(:phoenix_kit_templates_editor, key, value)

      assert ["shop_invoice", "shop_offer", "shop_draft"] =
               Enum.map(PhoenixKitTemplatesEditor.email_templates(), & &1.name)
    end

    test "nothing without catalog: true, or with a broken config", %{tmp_dir: root} do
      Application.put_env(:phoenix_kit_templates_editor, :root, root)
      Application.put_env(:phoenix_kit_templates_editor, :name_prefixes, ["shop_"])
      Application.put_env(:phoenix_kit_templates_editor, :locales, ["et"])
      assert PhoenixKitTemplatesEditor.email_templates() == []

      Application.put_env(:phoenix_kit_templates_editor, :catalog, "yes")
      assert PhoenixKitTemplatesEditor.email_templates() == []
    end
  end

  def samples, do: %{"order_number" => "42"}
end
