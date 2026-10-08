defmodule PhoenixKitTemplatesEditor.OverridingTest do
  # Files for an email core or a module sends (spec §4.11 П2): from its
  # built-in text, by language, evaluated in that language as core's preview
  # does; from the Emails module's active database template by that
  # module's own export; a module layout's part from the shared one or
  # core's.
  use ExUnit.Case, async: false

  alias PhoenixKit.Email.Layout
  alias PhoenixKitTemplatesEditor.Overriding
  alias PhoenixKitTemplatesEditor.Test.FakeProvider
  alias PhoenixKitTemplatesEditor.Test.FakeTemplateExport

  @moduletag :tmp_dir

  defp read(root, name, file), do: File.read(Path.join([root, name, file]))

  defp entry(defaults), do: %{name: "billing_invoice", label: "Invoice", defaults: defaults}

  describe "defaults/2" do
    test "the parts in the language asked, blank ones left out" do
      entry =
        entry(fn ->
          %{
            subject: "Arve " <> Gettext.get_locale(),
            markdown: "**{{n}}**",
            text: "  ",
            html: nil
          }
        end)

      assert Overriding.defaults(entry, "et") ==
               {:ok, %{subject: "Arve et", markdown: "**{{n}}**"}}
    end

    test "a map, none at all, and one that fails" do
      assert Overriding.defaults(entry(%{text: "T"}), "en") == {:ok, %{text: "T"}}
      assert Overriding.defaults(%{name: "x"}, "en") == {:ok, %{}}
      assert {:error, message} = Overriding.defaults(entry(fn -> raise "boom" end), "en")
      assert message =~ "boom"
    end
  end

  describe "from_defaults/3" do
    test "writes each part per language", %{tmp_dir: root} do
      entry = entry(fn -> %{subject: "S-" <> Gettext.get_locale(), markdown: "M"} end)

      assert {:ok, paths} = Overriding.from_defaults(root, entry, ["et", "en"])

      assert read(root, "billing_invoice", "subject.et.txt") == {:ok, "S-et"}
      assert read(root, "billing_invoice", "subject.en.txt") == {:ok, "S-en"}
      assert read(root, "billing_invoice", "markdown.et.md") == {:ok, "M"}
      assert hd(paths) == Path.join(root, "billing_invoice")
      refute File.exists?(Path.join([root, "billing_invoice", "subject.txt"]))
    end

    test "a layout in the defaults becomes layout.txt", %{tmp_dir: root} do
      assert {:ok, _paths} =
               Overriding.from_defaults(root, entry(%{text: "T", layout: "billing"}), ["en"])

      assert read(root, "billing_invoice", "layout.txt") == {:ok, "billing"}
    end

    test "never over files already there", %{tmp_dir: root} do
      File.mkdir_p!(Path.join(root, "billing_invoice"))
      File.write!(Path.join([root, "billing_invoice", "text.txt"]), "mine")

      assert Overriding.from_defaults(root, entry(%{text: "T"}), ["en"]) == {:error, :exists}
      assert read(root, "billing_invoice", "text.txt") == {:ok, "mine"}
    end

    test "nothing to write, or a failure: nothing is left behind", %{tmp_dir: root} do
      assert Overriding.from_defaults(root, entry(%{}), ["en"]) == {:error, :empty}

      assert {:error, _message} =
               Overriding.from_defaults(root, entry(fn -> raise "boom" end), ["en"])

      too_large = String.duplicate("a", PhoenixKit.Templates.Overrides.max_bytes() + 1)

      assert {:error, :too_large} =
               Overriding.from_defaults(root, entry(%{subject: "S", text: too_large}), ["en"])

      refute File.exists?(Path.join(root, "billing_invoice"))
    end
  end

  describe "from_db/2" do
    setup do
      previous = Application.get_env(:phoenix_kit_templates_editor, :template_export)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:phoenix_kit_templates_editor, :template_export, previous),
          else: Application.delete_env(:phoenix_kit_templates_editor, :template_export)
      end)
    end

    test "without the Emails module: nothing to export from" do
      refute Overriding.emails_module?()
      assert Overriding.from_db("/nowhere", "billing_invoice") == {:error, :no_emails_module}
    end

    test "the active row, by the Emails module's own export", %{tmp_dir: root} do
      Application.put_env(:phoenix_kit_templates_editor, :template_export, FakeTemplateExport)

      FakeProvider.put_db_templates(%{
        "billing_invoice" => %{
          name: "billing_invoice",
          is_system: false,
          subject: %{"en" => "Invoice", "et" => "Arve"},
          text_body: %{"en" => "Text"},
          html_body: %{"et" => "<p>Arve</p>"}
        }
      })

      assert Overriding.emails_module?()
      assert Overriding.db_template?("billing_invoice")
      refute Overriding.db_template?("other")

      assert {:ok, _paths} = Overriding.from_db(root, "billing_invoice")

      assert_received {:export_plan, "billing_invoice", opts}
      assert opts[:out] == root
      assert opts[:html] == :body

      assert read(root, "billing_invoice", "subject.txt") == {:ok, "Invoice"}
      assert read(root, "billing_invoice", "subject.et.txt") == {:ok, "Arve"}
      assert read(root, "billing_invoice", "html.et.html") == {:ok, "<p>Arve</p>"}
      assert Overriding.from_db(root, "other") == {:error, :no_db_template}
    end
  end

  describe "layout parts of a module's layout" do
    test "the shared part's HTML when the root has it, else core's", %{tmp_dir: root} do
      assert {:ok, footer} = Overriding.layout_default(root, "_footer-billing")

      assert footer in [
               Layout.default_footer_html(link: true),
               Layout.default_footer_html(link: false)
             ]

      File.mkdir_p!(Path.join(root, "_footer"))
      File.write!(Path.join([root, "_footer", "html.html"]), "<p>Shared</p>")

      assert Overriding.layout_default(root, "_footer-billing") == {:ok, "<p>Shared</p>"}
      assert Overriding.layout_default(root, "billing_invoice") == {:error, :not_a_layout_part}
    end

    test "from_layout_default/2 writes it without a language", %{tmp_dir: root} do
      assert {:ok, _paths} = Overriding.from_layout_default(root, "_layout-billing")
      assert {:ok, html} = read(root, "_layout-billing", "html.html")
      assert html =~ "{{{content}}}"
    end
  end
end
