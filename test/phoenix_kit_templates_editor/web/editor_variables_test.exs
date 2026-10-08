defmodule PhoenixKitTemplatesEditor.Web.EditorVariablesTest do
  # The variables panel (spec §4.11 П4): a part's variables with a sample
  # and the host's description, inserted with a click — at the cursor
  # through the module's JS hook, at the end of the body without it — and
  # checked on saving by the kind of template: a variable of the other kind
  # needs a confirmation, an unknown one is a warning, `{{{x}}}` only for
  # the HTML variables (Б9), a subject one line of at most 998 bytes (Б7).
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  defp file(root, name, file), do: File.read(Path.join([root, name, file]))

  defp insert(view, variable, parts) do
    view
    |> form("#editor-parts", parts: parts)
    |> put_submitter("#editor-variables button[value='insert:#{variable}']")
    |> render_submit()
  end

  describe "the panel" do
    test "an email: its variables with samples and descriptions, the branding for Markdown",
         %{tmp_dir: root} do
      seed(root)

      view =
        mount_editor(root, %{
          describe_variables: fn
            "order_offer" -> %{"order_number" => "The order's number"}
            _other -> %{}
          end
        })

      select(view, "order_offer")
      panel = view |> element("#editor-variables") |> render()

      assert panel =~ "{{order_number}}"
      assert panel =~ "37"
      assert panel =~ "The order&#39;s number"
      assert panel =~ "{{documents_list}}"
      assert has_element?(view, "#editor-variables-logo_url", "Markdown only")
      refute panel =~ "{{site_url}}"
    end

    test "a header: the layout's variables, not the email's", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "_header-shop")
      panel = view |> element("#editor-variables") |> render()

      assert panel =~ "{{site_name}}"
      assert panel =~ "{{site_url}}"
      refute panel =~ "{{order_number}}"
    end

    test "a describe_variables that fails describes nothing", %{tmp_dir: root} do
      seed(root)

      log =
        capture_log(fn ->
          view = mount_editor(root, %{describe_variables: fn _name -> raise "down" end})
          select(view, "order_offer")
          assert has_element?(view, "#editor-variables", "{{order_number}}")
        end)

      assert log =~ "describe_variables"
    end

    test "the insert buttons belong to the form and the hook; read only has none",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      assert has_element?(
               view,
               "#editor-variables button[form=editor-parts][name=action][value='insert:order_number']"
             )

      assert has_element?(view, "#editor-form[phx-hook=PhoenixKitTemplatesEditorInsertVariable]")

      view = mount_editor(root, %{editable: false})
      select(view, "order_offer")
      assert has_element?(view, "#editor-variables", "{{order_number}}")
      refute has_element?(view, "#editor-variables button")
    end
  end

  describe "inserting without JS" do
    test "goes at the end of the body, into the form only", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      insert(view, "order_number", %{text: "Tere!", subject: "Uus teema"})

      assert field(view, :text) == "Tere!{{order_number}}"
      assert field(view, :subject) == "Uus teema"
      assert {:ok, "Tere!\n\n{{documents_list}}\n"} = file(root, "order_offer", "text.et.txt")
    end

    test "Markdown is the body when it holds anything; a header's body is its HTML",
         %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")
      insert(view, "order_number", %{markdown: "**Tere**", text: "Tere"})
      assert field(view, :markdown) == "**Tere**{{order_number}}"
      assert field(view, :text) == "Tere"

      select(view, "_header-shop")
      tab(view, "")
      insert(view, "site_name", %{html: "<p>Shop</p>\n"})
      assert field(view, :html) == "<p>Shop</p>\n{{site_name}}"
    end

    test "a name that is not in the panel inserts nothing", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      view
      |> with_target("#editor")
      |> render_submit("save", %{"action" => "insert:site_url", "parts" => %{"text" => "x"}})

      assert {:ok, "Tere!\n\n{{documents_list}}\n"} = file(root, "order_offer", "text.et.txt")
      refute field(view, :text) =~ "site_url"
    end
  end

  describe "checked on saving" do
    test "a layout's variable in an email's body waits for a confirmation", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      html = save(view, %{text: "Vaata {{site_url}}"})

      assert html =~ "{{site_url}}"
      assert has_element?(view, "#editor-confirm-variables")
      assert {:ok, "Tere!\n\n{{documents_list}}\n"} = file(root, "order_offer", "text.et.txt")
      assert field(view, :text) == "Vaata {{site_url}}"
      refute_received {:after_write, _paths}

      view |> element("#editor-confirm-variables-save") |> render_click()

      assert {:ok, "Vaata {{site_url}}"} = file(root, "order_offer", "text.et.txt")
      refute has_element?(view, "#editor-confirm-variables")
    end

    test "cancelled, nothing is saved and the form keeps what was typed", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")
      save(view, %{text: "Vaata {{site_url}}"})

      view |> element("#editor-confirm-variables-cancel") |> render_click()

      refute has_element?(view, "#editor-confirm-variables")
      assert {:ok, "Tere!\n\n{{documents_list}}\n"} = file(root, "order_offer", "text.et.txt")
      assert field(view, :text) == "Vaata {{site_url}}"
    end

    test "the confirmation asks the host's authorize again", %{tmp_dir: root} do
      seed(root)
      test_pid = self()
      allowed = :counters.new(1, [])
      :counters.put(allowed, 1, 1)

      authorize = fn _action ->
        send(test_pid, :asked)
        if :counters.get(allowed, 1) == 1, do: :ok, else: {:error, :forbidden}
      end

      view = mount_editor(root, %{authorize: authorize})
      select(view, "order_offer")
      save(view, %{text: "Vaata {{site_url}}"})

      :counters.put(allowed, 1, 0)
      html = view |> element("#editor-confirm-variables-save") |> render_click()

      assert html =~ "not allowed"
      assert {:ok, "Tere!\n\n{{documents_list}}\n"} = file(root, "order_offer", "text.et.txt")
    end

    test "an email's variable in a header waits for a confirmation too", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "_header-shop")
      tab(view, "")

      save(view, %{html: "<p>{{order_number}}</p>"})

      assert has_element?(view, "#editor-confirm-variables", "{{order_number}}")
      assert {:ok, "<p>Shop</p>\n"} = file(root, "_header-shop", "html.html")
    end

    test "an unknown variable is saved, with a warning", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      html = save(view, %{text: "Tere {{nope}}"})

      assert {:ok, "Tere {{nope}}"} = file(root, "order_offer", "text.et.txt")
      assert html =~ "Saved. But: {{nope}} is not a variable of this template"
    end

    test "three braces only for the host's raw variables; refused otherwise", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{raw_variables: ["documents_list"]})
      select(view, "order_offer")

      html = save(view, %{html: "<div>{{{order_number}}}</div>"})
      assert html =~ "{{{order_number}}}"
      refute has_element?(view, "#editor-confirm-variables")
      assert {:error, :enoent} = file(root, "order_offer", "html.et.html")

      save(view, %{html: "<div>{{{documents_list}}}</div>"})
      assert {:ok, "<div>{{{documents_list}}}</div>"} = file(root, "order_offer", "html.et.html")
    end

    test "with no variable allowed three braces, the refusal says none is", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      html = save(view, %{html: "<div>{{{order_number}}}</div>"})

      assert html =~
               "Write them with two braces: no variable is written with three here."

      refute html =~ "only for"
      assert {:error, :enoent} = file(root, "order_offer", "html.et.html")
    end

    test "a page layout places content, header and footer with three braces", %{tmp_dir: root} do
      seed(root)
      put(root, "_layout-shop", "html.html", "<html>{{{content}}}</html>")
      view = mount_editor(root)
      select(view, "_layout-shop")
      tab(view, "")

      save(view, %{html: "<html>{{{header}}}{{{content}}}{{{footer}}}</html>"})

      assert {:ok, "<html>{{{header}}}{{{content}}}{{{footer}}}</html>"} =
               file(root, "_layout-shop", "html.html")
    end

    test "a subject is one line of at most 998 bytes", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root)
      select(view, "order_offer")

      assert save(view, %{subject: "One\nTwo"}) =~ "one line"
      assert save(view, %{subject: String.duplicate("a", 999)}) =~ "998"
      assert {:ok, "Pakkumine {{order_number}}\n"} = file(root, "order_offer", "subject.et.txt")

      save(view, %{subject: String.duplicate("a", 998) <> "\n"})
      assert {:ok, _subject} = file(root, "order_offer", "subject.et.txt")
      refute file(root, "order_offer", "subject.et.txt") == {:ok, "Pakkumine {{order_number}}\n"}
    end
  end
end
