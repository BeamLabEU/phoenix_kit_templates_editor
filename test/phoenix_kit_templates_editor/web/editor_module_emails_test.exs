defmodule PhoenixKitTemplatesEditor.Web.EditorModuleEmailsTest do
  # "Module emails": the emails core
  # and other modules send, read only until they have a file; a file made
  # from the built-in text where the email is overridable; where each part
  # of such an email comes from; the sign-in emails only by name, with a
  # warning; a module's own layout group the same way.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  @invoice %{
    name: "billing_invoice",
    label: "Invoice",
    description: "Sent when an invoice is issued.",
    defaults: %{subject: "Invoice {{n}}", markdown: "Pay **{{n}}**"},
    variables: %{"n" => "INV-1"},
    layout: "billing"
  }

  @reset %{
    name: "reset_password",
    label: "Password reset",
    defaults: %{subject: "Reset", markdown: "[Reset]({{reset_url}})"},
    variables: %{"reset_url" => "https://x/reset"}
  }

  defp mount_modules(root, opts \\ %{}) do
    test_pid = self()

    mount_editor(
      root,
      Map.merge(
        %{
          module_emails: [@invoice, @reset],
          reserved_names: ["billing_invoice", "reset_password"],
          overridable: :all,
          layout_group: "shop",
          layout_groups: ["shop"],
          journal: fn event -> send(test_pid, {:journal, event}) end
        },
        opts
      )
    )
  end

  defp open_module(view, name) do
    view
    |> element("#editor-module-emails [phx-click=select_module][phx-value-name=#{name}]")
    |> render_click()
  end

  defp file(root, name, file), do: File.read(Path.join([root, name, file]))

  describe "the list" do
    test "every module email, with its label and whether it has a file", %{tmp_dir: root} do
      seed(root)
      view = mount_modules(root)

      list = view |> element("#editor-module-emails") |> render()
      assert list =~ "Invoice"
      assert list =~ "Password reset"
      assert list =~ "built-in text"
      refute has_element?(view, "#editor-messages [phx-value-name=billing_invoice]")
    end

    test "none passed, no section", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      refute has_element?(view, "#editor-module-emails")
    end
  end

  describe "an email without a file" do
    test "is shown read only: its built-in text and where each part comes from",
         %{tmp_dir: root} do
      seed(root)
      view = mount_modules(root)
      open_module(view, "billing_invoice")

      module = view |> element("#editor-module-email") |> render()
      assert module =~ "Sent when an invoice is issued."
      assert module =~ "Invoice {{n}}"
      assert module =~ "Pay **{{n}}**"
      assert view |> element("#editor-module-email-sources") |> render() =~ "built-in text"
      refute has_element?(view, "#editor-parts")
      assert has_element?(view, "#editor-module-email-variables", "{{n}}")
    end

    test "a file from the built-in text, in every language, then edited as usual",
         %{tmp_dir: root} do
      seed(root)
      view = mount_modules(root)
      open_module(view, "billing_invoice")

      assert render(view) =~ "no longer reach"

      html = view |> element("#editor-module-create-default") |> render_click()

      assert html =~ "from its built-in text"
      assert file(root, "billing_invoice", "subject.et.txt") == {:ok, "Invoice {{n}}"}
      assert file(root, "billing_invoice", "markdown.en.md") == {:ok, "Pay **{{n}}**"}
      assert_received {:after_write, [_dir | _files]}
      assert_received {:after_change, "billing_invoice"}
      assert_received {:journal, %{action: :created_from_default, template: "billing_invoice"}}

      assert has_element?(view, "#editor-parts")
      assert field(view, :subject) == "Invoice {{n}}"
      assert view |> element("#editor-module-emails") |> render() =~ "file"
      assert view |> element("#editor-sources") |> render() =~ "this file"
    end

    test "read only: shown, no button; a forged event writes nothing", %{tmp_dir: root} do
      seed(root)
      view = mount_modules(root, %{editable: false})
      open_module(view, "billing_invoice")

      refute has_element?(view, "#editor-module-create-default")

      view
      |> with_target("#editor")
      |> render_click("override_default", %{"name" => "billing_invoice"})

      refute File.exists?(Path.join(root, "billing_invoice"))
    end

    test "a host's authorize that refuses: nothing written", %{tmp_dir: root} do
      seed(root)
      view = mount_modules(root, %{authorize: fn _action -> {:error, :forbidden} end})
      open_module(view, "billing_invoice")

      assert view |> element("#editor-module-create-default") |> render_click() =~ "not allowed"
      refute File.exists?(Path.join(root, "billing_invoice"))
    end
  end

  describe "the sign-in emails" do
    test "not overridable by :all: no button, and a forged event writes nothing",
         %{tmp_dir: root} do
      seed(root)
      view = mount_modules(root)
      open_module(view, "reset_password")

      assert has_element?(view, "#editor-module-email-not-overridable")
      refute has_element?(view, "#editor-module-create-default")

      view
      |> with_target("#editor")
      |> render_click("override_default", %{"name" => "reset_password"})

      refute File.exists?(Path.join(root, "reset_password"))
    end

    test "overridable by name, with a warning", %{tmp_dir: root} do
      seed(root)
      view = mount_modules(root, %{overridable: ["reset_password"]})
      open_module(view, "reset_password")

      assert has_element?(view, "#editor-auth-warning")
      view |> element("#editor-module-create-default") |> render_click()

      assert {:ok, "Reset"} = file(root, "reset_password", "subject.et.txt")
      assert has_element?(view, "#editor-auth-warning")
    end
  end

  describe "an email with a file" do
    test "opens in the editor from the list; the plain create form still refuses the name",
         %{tmp_dir: root} do
      seed(root)
      put(root, "billing_invoice", "subject.et.txt", "Arve {{n}}")
      view = mount_modules(root)

      view
      |> element("#editor-module-emails [phx-click=select][phx-value-name=billing_invoice]")
      |> render_click()

      assert field(view, :subject) == "Arve {{n}}"
      assert has_element?(view, "#editor-variables", "{{n}}")
      assert create(view, "billing_receipt") =~ "not allowed here"
      assert create(view, "reset_password") =~ "sends this email"
    end

    test "not overridable: listed, shown read only", %{tmp_dir: root} do
      seed(root)
      put(root, "billing_invoice", "subject.et.txt", "Arve")
      view = mount_modules(root, %{overridable: []})

      open_module(view, "billing_invoice")
      assert has_element?(view, "#editor-module-email-not-overridable")
      refute has_element?(view, "#editor-parts")
    end
  end

  describe "who sends an email" do
    test "the host's own: the file is what is used", %{tmp_dir: root} do
      seed(root)
      view = mount_modules(root)
      select(view, "order_offer")

      assert has_element?(view, "#editor-sent-by-host")
      refute has_element?(view, "#editor-sources")
    end

    test "sent_by may say core sends one of the host's", %{tmp_dir: root} do
      seed(root)
      view = mount_modules(root, %{sent_by: fn _name -> :core end})
      select(view, "order_offer")

      refute has_element?(view, "#editor-sent-by-host")
      assert view |> element("#editor-sources") |> render() =~ "this file"
    end
  end

  describe "a module's layout" do
    test "its parts from the shared one or core's, then under Layouts", %{tmp_dir: root} do
      seed(root)
      view = mount_modules(root)

      assert has_element?(view, "#editor-module-layout-billing")
      view |> element("#editor-module-layout-billing-header-create") |> render_click()

      assert {:ok, _html} = file(root, "_header-billing", "html.html")
      assert has_element?(view, "#editor-layout-billing [phx-value-name=_header-billing]")
      assert field(view, :html) != ""
      assert_received {:journal, %{action: :created_from_default, template: "_header-billing"}}
    end
  end
end
