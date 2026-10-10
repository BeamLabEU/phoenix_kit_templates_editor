defmodule PhoenixKitTemplatesEditor.SourcesTest do
  # Where each part of an email core sends comes from,
  # through core's own resolution: the Emails module's database template,
  # a file of the root (blank or not), or the built-in text.
  use ExUnit.Case, async: false

  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Sources
  alias PhoenixKitTemplatesEditor.Test.FakeProvider

  @moduletag :tmp_dir

  @entry %{
    name: "billing_invoice",
    label: "Invoice",
    defaults: %{subject: "Built-in subject", markdown: "Built-in body"}
  }

  defp put(root, file, content) do
    File.mkdir_p!(Path.join(root, "billing_invoice"))
    File.write!(Path.join([root, "billing_invoice", file]), content)
    Overrides.reset_cache([root])
  end

  test "a file, a blank file and the built-in text, part by part", %{tmp_dir: root} do
    put(root, "subject.et.txt", "Arve")
    put(root, "text.txt", "  ")

    assert {:ok, sources} = Sources.of(root, "billing_invoice", "et", @entry)

    assert sources.subject == {:file, Path.join([root, "billing_invoice", "subject.et.txt"])}
    assert sources.text == {:blank_file, Path.join([root, "billing_invoice", "text.txt"])}
    assert sources.markdown == :default
    assert sources.html == nil
    assert sources.html_from == :markdown
    refute sources.db?
  end

  test "no entry: only the files", %{tmp_dir: root} do
    put(root, "text.en.txt", "Hi")

    assert {:ok, sources} = Sources.of(root, "billing_invoice", "en", nil)
    assert sources.text == {:file, Path.join([root, "billing_invoice", "text.en.txt"])}
    assert sources.subject == nil
  end

  test "an active database template wins over every file", %{tmp_dir: root} do
    put(root, "subject.en.txt", "From the file")

    FakeProvider.put_db_templates(%{
      "billing_invoice" => %{
        name: "billing_invoice",
        subject: %{"en" => "From the database"},
        text_body: %{"en" => "Body"},
        html_body: %{"en" => "<p>Body</p>"}
      }
    })

    assert {:ok, sources} = Sources.of(root, "billing_invoice", "en", @entry)
    assert sources.db?
    assert sources.subject == :db
    assert sources.html == :db
  end

  test "a built-in text that fails is an error, not a crash", %{tmp_dir: root} do
    entry = %{@entry | defaults: fn -> raise "boom" end}
    assert {:error, message} = Sources.of(root, "billing_invoice", "en", entry)
    assert message =~ "boom"
  end
end
