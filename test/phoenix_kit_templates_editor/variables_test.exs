defmodule PhoenixKitTemplatesEditor.VariablesTest do
  # Which placeholders a part may hold an email's
  # body has the email's variables (and the branding in Markdown, or
  # everywhere when core sends it), a header or footer the layout's, the page
  # layout the layout's and the rendered content, header and footer — and
  # `{{{x}}}` only for the HTML variables.
  use ExUnit.Case, async: true

  alias PhoenixKitTemplatesEditor.Variables

  @layout %{
    "subject" => "",
    "site_name" => "Shop",
    "site_url" => "https://shop.test",
    "logo_url" => "",
    "accent_color" => "#112233"
  }

  defp context(name, overrides \\ %{}) do
    Variables.context(
      name,
      Map.merge(
        %{
          email: %{"order_number" => "37", "documents_list" => "- a.pdf"},
          layout: @layout,
          raw: [],
          sent_by: :host
        },
        Map.new(overrides)
      )
    )
  end

  describe "kind/1" do
    test "an email, a header or footer, a page layout" do
      assert Variables.kind("shop_offer") == :email
      assert Variables.kind("_header-shop") == :chrome
      assert Variables.kind("_footer") == :chrome
      assert Variables.kind("_layout-shop") == :layout
      assert Variables.kind("_layout") == :layout
      assert Variables.kind("_other") == :chrome
    end
  end

  describe "placeholders/1" do
    test "each name once, double and triple braces told apart" do
      assert Variables.placeholders("{{a}} {{ b }} {{{c}}} {{{ a }}} {{a}}") ==
               %{double: ["a", "b"], triple: ["c", "a"]}
    end

    test "braces that make no placeholder are text" do
      assert Variables.placeholders("body { margin: 0 } {{1x}} {x}") ==
               %{double: [], triple: []}
    end
  end

  describe "check/3 on an email" do
    test "its own variables pass; a layout variable is forbidden here; others unknown" do
      ctx = context("shop_offer")

      assert Variables.check("Order {{order_number}}", :subject, ctx) ==
               %{forbidden: [], unknown: [], raw: []}

      assert Variables.check("See {{site_url}} and {{nope}}", :text, ctx) ==
               %{forbidden: ["site_url"], unknown: ["nope"], raw: []}
    end

    test "the branding: in Markdown for an email the host sends, everywhere when core does" do
      host = context("shop_offer")
      assert Variables.check("{{logo_url}}", :markdown, host).forbidden == []
      assert Variables.check("{{logo_url}}", :html, host).forbidden == ["logo_url"]

      core = context("shop_offer", sent_by: :core)
      assert Variables.check("{{logo_url}}", :html, core).forbidden == []
    end

    test "an email that passes a layout variable itself may use it" do
      ctx = context("welcome", email: %{"site_url" => "https://x"})
      assert Variables.check("{{site_url}}", :text, ctx).forbidden == []
    end

    test "triple braces only for the host's raw variables" do
      ctx = context("shop_offer", raw: ["documents_list"])

      assert Variables.check("{{{documents_list}}}", :html, ctx).raw == []
      assert Variables.check("{{{order_number}}}", :html, ctx).raw == ["order_number"]
      assert Variables.check("{{{content}}}", :html, ctx).raw == ["content"]
    end

    test "the label is never sent: nothing to check" do
      assert Variables.check("{{{x}}} {{site_url}}", :label, context("shop_offer")) ==
               %{forbidden: [], unknown: [], raw: []}
    end
  end

  describe "check/3 on layout parts" do
    test "a header has the layout's variables; an email's, or the page layout's, is forbidden there" do
      ctx = context("_header-shop")

      assert Variables.check("{{site_name}} {{logo_url}}", :html, ctx) ==
               %{forbidden: [], unknown: [], raw: []}

      assert Variables.check("{{order_number}} {{{content}}} {{x}}", :html, ctx) ==
               %{forbidden: ["order_number", "content"], unknown: ["x"], raw: ["content"]}
    end

    test "the page layout places content, header and footer raw" do
      ctx = context("_layout-shop")

      assert Variables.check("{{{header}}}{{{content}}}{{{footer}}}{{subject}}", :html, ctx) ==
               %{forbidden: [], unknown: [], raw: []}
    end
  end

  describe "panel/2" do
    test "an email: its variables with samples and the host's descriptions, then the branding" do
      ctx = context("shop_offer", descriptions: %{"order_number" => "The order's number"})

      assert [
               %{name: "documents_list", sample: "- a.pdf", description: nil, scope: :all},
               %{name: "order_number", sample: "37", description: "The order's number"},
               %{name: "accent_color", scope: :markdown},
               %{name: "logo_url", scope: :markdown}
             ] = Variables.panel(ctx)
    end

    test "a page layout: the layout's variables, then the HTML ones" do
      names = context("_layout-shop") |> Variables.panel() |> Enum.map(& &1.name)

      assert names ==
               ~w(accent_color logo_url site_name site_url subject content footer header)
    end

    test "a sample that is no string is shown as Elixir would print it" do
      [row] = Variables.panel(context("shop_offer", email: %{"n" => 37}, layout: %{}))
      assert row.sample == "37"
    end
  end

  describe "layout_variables/1" do
    test "core's layout variables with the site's values, read without any file" do
      variables = Variables.layout_variables(nil)
      assert Map.keys(variables) |> Enum.sort() == Enum.sort(Map.keys(@layout))
    end
  end
end
