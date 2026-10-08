defmodule PhoenixKitTemplatesEditor.Integration.PreviewTest do
  # The module's own preview, for a host that gives none (spec §4.5): an
  # email's parts from the root by its language chain, the HTML body from
  # html, else Markdown, else text; the text body from text, else Markdown,
  # else the HTML; the sample variables (and the branding) filled in; the
  # chrome of the email's layout group around it. A header, footer or layout
  # is shown around the first email, or a Lorem ipsum when there is none.
  use PhoenixKitTemplatesEditor.DataCase, async: false

  alias PhoenixKit.Email.Branding
  alias PhoenixKit.Settings
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Config
  alias PhoenixKitTemplatesEditor.Converters
  alias PhoenixKitTemplatesEditor.Preview

  @moduletag :tmp_dir

  setup %{tmp_dir: root} do
    on_exit(fn -> Overrides.reset_cache([root]) end)

    put(root, "_header-shop", "html.html", "<div>SHOP-HEADER</div>")
    put(root, "_footer-shop", "html.html", "<div>SHOP-FOOTER</div>")
    put(root, "_footer-shop-supplier", "html.html", "<div>SUPPLIER-FOOTER</div>")
    :ok
  end

  defp put(root, name, file, content) do
    File.mkdir_p!(Path.join(root, name))
    File.write!(Path.join([root, name, file]), content)
  end

  # The library's cache entries for template `name` under `root`.
  defp cached(root, name) do
    for {{Overrides, :located, roots, ^name, _part, _locale}, _value} <- :persistent_term.get(),
        root in roots,
        do: name
  end

  defp config(root, overrides \\ []) do
    {:ok, config} =
      Config.load(
        Keyword.merge(
          [
            root: root,
            name_prefixes: ["shop_", "_header-shop", "_footer-shop", "_layout-shop"],
            locales: ["et", "ru"],
            layout_group: "shop",
            layout_groups: ["shop"],
            sample_variables: %{"order_number" => "37", "customer_name" => "Mari"}
          ],
          overrides
        )
      )

    config
  end

  describe "an email" do
    test "its HTML in the group's chrome, its subject and text filled in", %{tmp_dir: root} do
      put(root, "shop_offer", "subject.et.txt", "Offer {{order_number}}\n")
      put(root, "shop_offer", "html.et.html", "<p>Hello, {{customer_name}}!</p>")
      put(root, "shop_offer", "text.et.txt", "Hello, {{customer_name}}! Text.")

      assert {"Offer 37", html, "Hello, Mari! Text."} =
               Preview.preview(config(root), "shop_offer", "et")

      assert html =~ "<p>Hello, Mari!</p>"
      assert html =~ "SHOP-HEADER"
      assert html =~ "SHOP-FOOTER"
      assert html =~ ~r/<html[^>]*lang="et"/
    end

    test "Markdown only: HTML and text made from it, with the accent colour",
         %{tmp_dir: root} do
      Settings.update_setting(Branding.accent_color_key(), "#1d4ed8")
      put(root, "shop_offer", "subject.et.txt", "Offer")

      put(
        root,
        "shop_offer",
        "markdown.et.md",
        "Hello, **{{customer_name}}**!\n\n[Pay](https://pay.example.com/{{order_number}})"
      )

      assert {"Offer", html, text} = Preview.preview(config(root), "shop_offer", "et")

      assert html =~ "<strong>Mari</strong>"
      assert html =~ "background-color:#1d4ed8"
      assert html =~ ~s(href="https://pay.example.com/37")
      assert text == "Hello, Mari!\n\nPay: https://pay.example.com/37"
    end

    test "text only: HTML made of its paragraphs", %{tmp_dir: root} do
      put(root, "shop_offer", "subject.et.txt", "Offer")
      put(root, "shop_offer", "text.et.txt", "First {{order_number}}\n\nSecond")

      assert {"Offer", html, "First 37\n\nSecond"} =
               Preview.preview(config(root), "shop_offer", "et")

      assert html =~ ~r{<p[^>]*>First 37</p>}
      assert html =~ "SHOP-HEADER"
    end

    test "HTML only: the text made from it", %{tmp_dir: root} do
      put(root, "shop_offer", "subject.et.txt", "Offer")
      put(root, "shop_offer", "html.et.html", "<p>One</p><p>Two {{order_number}}</p>")

      assert {"Offer", _html, "One\n\nTwo 37"} = Preview.preview(config(root), "shop_offer", "et")
    end

    test "a blank file is no part", %{tmp_dir: root} do
      put(root, "shop_offer", "subject.et.txt", "Offer")
      put(root, "shop_offer", "html.et.html", "  \n")
      put(root, "shop_offer", "text.et.txt", "From text")

      assert {"Offer", html, "From text"} = Preview.preview(config(root), "shop_offer", "et")
      assert html =~ "From text"
    end

    test "the chrome of the group its layout.txt names", %{tmp_dir: root} do
      put(root, "shop_offer", "subject.et.txt", "Offer")
      put(root, "shop_offer", "text.et.txt", "Body")
      put(root, "shop_offer", "layout.txt", "shop-supplier\n")

      {_subject, html, _text} = Preview.preview(config(root), "shop_offer", "et")

      assert html =~ "SUPPLIER-FOOTER"
      assert html =~ "SHOP-HEADER" == false
    end

    test "a whole document is not wrapped", %{tmp_dir: root} do
      put(root, "shop_offer", "html.et.html", "<!DOCTYPE html><html><body>OWN</body></html>")

      assert {nil, "<!DOCTYPE html><html><body>OWN</body></html>", "OWN"} =
               Preview.preview(config(root), "shop_offer", "et")
    end

    test "a language without its own file takes the next in its chain", %{tmp_dir: root} do
      put(root, "shop_offer", "subject.txt", "Fallback subject")
      put(root, "shop_offer", "text.txt", "Fallback text")

      assert {"Fallback subject", _html, "Fallback text"} =
               Preview.preview(config(root), "shop_offer", "ru")

      assert {"Fallback subject", _html, "Fallback text"} =
               Preview.preview(config(root), "shop_offer", nil)
    end
  end

  describe "a header, footer or layout" do
    setup %{tmp_dir: root} do
      put(root, "shop_b", "label.et.txt", "B first by label")
      put(root, "shop_b", "subject.et.txt", "Subject B")
      put(root, "shop_b", "text.et.txt", "Body of B")
      put(root, "shop_a", "label.et.txt", "Z last by label")
      put(root, "shop_a", "text.et.txt", "Body of A")
      :ok
    end

    test "around the first email by label, in the group of its own name", %{tmp_dir: root} do
      assert {"Subject B", html, "Body of B"} =
               Preview.preview(config(root), "_header-shop", "et")

      assert html =~ "SHOP-HEADER"
      assert html =~ "Body of B"

      {_subject, html, _text} = Preview.preview(config(root), "_footer-shop-supplier", "et")
      assert html =~ "SUPPLIER-FOOTER"
      refute html =~ "SHOP-HEADER"
    end

    test "around the first email of that layout, else the first email", %{tmp_dir: root} do
      put(root, "shop_a", "layout.txt", "shop-supplier")

      {_subject, html, _text} = Preview.preview(config(root), "_footer-shop-supplier", "et")
      assert html =~ "SUPPLIER-FOOTER"
      assert html =~ "Body of A"

      {_subject, html, _text} = Preview.preview(config(root), "_header-shop", "et")
      assert html =~ "Body of B"

      {_subject, html, _text} = Preview.preview(config(root), "_footer-shop-new", "et")
      assert html =~ "Body of B"
    end

    test "a shared part in no group: the shared chrome, not the default group's",
         %{tmp_dir: root} do
      put(root, "_header", "html.html", "<div>SHARED-HEADER</div>")

      {_subject, html, _text} =
        Preview.preview(config(root, shared_layout_editable: true), "_header", "et")

      assert html =~ "SHARED-HEADER"
      refute html =~ "SHOP-HEADER"
    end

    test "around a Lorem ipsum when there is no email", %{tmp_dir: root} do
      File.rm_rf!(Path.join(root, "shop_a"))
      File.rm_rf!(Path.join(root, "shop_b"))

      assert {"Lorem ipsum", html, text} = Preview.preview(config(root), "_footer-shop", "et")
      assert html =~ "SHOP-FOOTER"
      assert html =~ "Lorem ipsum dolor sit amet"
      assert text =~ "Lorem ipsum dolor sit amet"
    end
  end

  describe "what it refuses" do
    test "a part file that is a link: an error naming it relative to the root", %{tmp_dir: root} do
      put(root, "shop_offer", "notes.txt", "SECRET")
      File.ln_s!("notes.txt", Path.join([root, "shop_offer", "text.et.txt"]))

      assert {:error, message} = Preview.preview(config(root), "shop_offer", "et")
      assert message =~ "shop_offer/text.et.txt"
      refute message =~ root
      refute message =~ "SECRET"
    end

    test "a chrome file that is a link", %{tmp_dir: root} do
      put(root, "shop_offer", "text.et.txt", "Body")
      put(root, "_header-shop", "notes.txt", "SECRET")
      File.rm!(Path.join([root, "_header-shop", "html.html"]))
      File.ln_s!("notes.txt", Path.join([root, "_header-shop", "html.html"]))

      assert {:error, message} = Preview.preview(config(root), "shop_offer", "et")
      assert message =~ "_header-shop/html.html"
    end

    # Checked before the library reads: `Overrides.locate/4` follows a link
    # and keeps what it read in `:persistent_term`.
    test "a link is refused before anything of the template is read", %{tmp_dir: root} do
      put(root, "shop_offer", "subject.et.txt", "Offer")
      File.ln_s!("/etc/hostname", Path.join([root, "shop_offer", "text.et.txt"]))

      assert {:error, message} = Preview.preview(config(root), "shop_offer", "et")
      assert message =~ "shop_offer/text.et.txt"
      assert cached(root, "shop_offer") == []
    end

    test "a chrome link is refused before the chrome is read", %{tmp_dir: root} do
      put(root, "shop_offer", "text.et.txt", "Body")
      File.ln_s!("/etc/hostname", Path.join([root, "_footer-shop", "html.et.html"]))

      assert {:error, message} = Preview.preview(config(root), "shop_offer", "et")
      assert message =~ "_footer-shop/html.et.html"
      assert cached(root, "_footer-shop") == []
    end

    test "work past the deadline", %{tmp_dir: root} do
      put(root, "shop_offer", "markdown.et.md", String.duplicate("**bold** text\n\n", 10_000))

      assert {:error, message} = Preview.preview(config(root), "shop_offer", "et", timeout: 0)
      assert message =~ "took too long"
    end
  end

  test "the host's sample variables from a callback", %{tmp_dir: root} do
    put(root, "shop_offer", "subject.et.txt", "Offer {{order_number}}")

    assert {"Offer 42", _html, _text} =
             Preview.preview(
               config(root, sample_variables: fn -> %{"order_number" => "42"} end),
               "shop_offer",
               "et"
             )
  end

  test "markdown_to_html writes the configured accent colour" do
    Settings.update_setting(Branding.accent_color_key(), "#1d4ed8")

    assert Converters.markdown_to_html("[Pay](https://pay.example.com)") =~
             "background-color:#1d4ed8"
  end
end
