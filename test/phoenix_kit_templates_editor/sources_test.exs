defmodule PhoenixKitTemplatesEditor.SourcesTest do
  # Where each part of an email core sends comes from,
  # through core's own resolution: the Emails module's database template,
  # a file of the root (blank or not), or the built-in text.
  use ExUnit.Case, async: false

  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Sources

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
  end

  test "no entry: only the files", %{tmp_dir: root} do
    put(root, "text.en.txt", "Hi")

    assert {:ok, sources} = Sources.of(root, "billing_invoice", "en", nil)
    assert sources.text == {:file, Path.join([root, "billing_invoice", "text.en.txt"])}
    assert sources.subject == nil
  end

  test "a built-in text that fails is an error, not a crash", %{tmp_dir: root} do
    entry = %{@entry | defaults: fn -> raise "boom" end}
    assert {:error, message} = Sources.of(root, "billing_invoice", "en", entry)
    assert message =~ "boom"
  end

  test "a linked file is refused without caching its contents", %{tmp_dir: root} do
    put(root, "notes.txt", "private")
    path = Path.join([root, "billing_invoice", "subject.en.txt"])
    File.ln_s!("notes.txt", path)
    on_exit(fn -> Overrides.reset_cache([root]) end)

    assert {:error, message} = Sources.of(root, "billing_invoice", "en", @entry)
    assert message =~ "billing_invoice/subject.en.txt"
    refute message =~ root

    File.rm!(path)
    File.write!(path, "Safe")
    assert Overrides.read([root], "billing_invoice", :subject, "en") == "Safe"
  end

  test "an oversized file is refused before resolution", %{tmp_dir: root} do
    put(root, "subject.en.txt", String.duplicate("x", Overrides.max_bytes() + 1))

    assert {:error, message} = Sources.of(root, "billing_invoice", "en", @entry)
    assert message =~ "larger than"
    refute message =~ root
  end

  test "chrome selected by an entry, a file or a defaults callback is checked", %{tmp_dir: root} do
    put(root, "text.en.txt", "Body")
    File.mkdir_p!(Path.join(root, "_footer-billing"))

    File.ln_s!(
      "../billing_invoice/text.en.txt",
      Path.join([root, "_footer-billing", "html.html"])
    )

    on_exit(fn -> Overrides.reset_cache([root]) end)

    entries = [
      Map.put(@entry, :layout, "billing"),
      %{@entry | defaults: fn -> %{text: "Body", layout: "billing"} end}
    ]

    for entry <- entries do
      assert {:error, message} = Sources.of(root, "billing_invoice", "en", entry)
      assert message =~ "_footer-billing/html.html"
    end

    put(root, "layout.txt", "billing")
    assert {:error, message} = Sources.of(root, "billing_invoice", "en", @entry)
    assert message =~ "_footer-billing/html.html"

    path = Path.join([root, "_footer-billing", "html.html"])
    File.rm!(path)
    File.write!(path, "Safe footer")
    assert Overrides.read([root], "_footer-billing", :html, "en") == "Safe footer"
  end
end
