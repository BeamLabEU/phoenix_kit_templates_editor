defmodule PhoenixKitTemplatesEditor.Web.EditorTestSendTest do
  # "Send to me" in the editor: a button on an email, the
  # host's `test_send` called with the email and the tab's language, what
  # it answers told — read only too.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  defp sender(test_pid, answer \\ {:ok, "me@example.com"}) do
    fn name, locale ->
      send(test_pid, {:test_send, name, locale})
      answer
    end
  end

  test "an email: sent in the tab's language, and said so", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root, %{test_send: sender(self())})
    select(view, "order_offer")
    tab(view, "ru")

    html = view |> element("#editor-test-send") |> render_click()

    assert_received {:test_send, "order_offer", "ru"}
    assert html =~ "Sent to me@example.com."
  end

  test "read only too: it writes nothing", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root, %{editable: false, test_send: sender(self())})
    select(view, "order_offer")

    view |> element("#editor-test-send") |> render_click()
    assert_received {:test_send, "order_offer", "et"}
  end

  test "the host's refusal is told", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root, %{test_send: sender(self(), {:error, "wait 12 s."})})
    select(view, "order_offer")

    assert view |> element("#editor-test-send") |> render_click() =~ "Not sent: wait 12 s."
  end

  test "not for a layout part, a draft, or without a callback", %{tmp_dir: root} do
    seed(root)
    view = mount_editor(root, %{test_send: sender(self())})
    select(view, "_header-shop")
    refute has_element?(view, "#editor-test-send")

    create(view, "order_new")
    refute has_element?(view, "#editor-test-send")

    view = mount_editor(root)
    select(view, "order_offer")
    refute has_element?(view, "#editor-test-send")
  end

  test "a module's email shown read only has it as well", %{tmp_dir: root} do
    seed(root)

    view =
      mount_editor(root, %{
        test_send: sender(self()),
        module_emails: [%{name: "billing_invoice", label: "Invoice", defaults: %{text: "T"}}],
        reserved_names: ["billing_invoice"]
      })

    view
    |> element("#editor-module-emails [phx-click=select_module][phx-value-name=billing_invoice]")
    |> render_click()

    view |> element("#editor-test-send") |> render_click()
    assert_received {:test_send, "billing_invoice", "et"}
  end

  test "a module email's own layout is checked before sending", %{tmp_dir: root} do
    seed(root)
    put(root, "_footer-billing", "notes.txt", "Private")
    File.ln_s!("notes.txt", Path.join([root, "_footer-billing", "html.html"]))

    view =
      mount_editor(root, %{
        test_send: sender(self()),
        layout_group: "shop",
        module_emails: [
          %{name: "billing_invoice", label: "Invoice", layout: "billing", defaults: %{text: "T"}}
        ],
        reserved_names: ["billing_invoice"]
      })

    view
    |> element("#editor-module-emails [phx-click=select_module][phx-value-name=billing_invoice]")
    |> render_click()

    html = view |> element("#editor-test-send") |> render_click()
    assert html =~ "Not sent"
    assert html =~ "_footer-billing/html.html"
    refute_received {:test_send, _, _}
  end
end
