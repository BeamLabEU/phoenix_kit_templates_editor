defmodule PhoenixKitTemplatesEditor.Web.EditorAccessTest do
  # Every event that changes something asks the server twice: is the editor
  # editable (strictly `true`), and does the host's `authorize` allow it.
  use PhoenixKitTemplatesEditor.EditorCase, async: true

  @convert %{to_text: {Host, :to_text}, markdown_to_html: {Host, :markdown_to_html}}
  @refused "You are not allowed to change templates"
  @read_only "These templates are read-only here"

  defp denying(test_pid) do
    fn action ->
      send(test_pid, {:authorize, action})
      {:error, :forbidden}
    end
  end

  defp allowing(test_pid) do
    fn action ->
      send(test_pid, {:authorize, action})
      :ok
    end
  end

  defp subject_et(root), do: File.read!(Path.join([root, "order_offer", "subject.et.txt"]))

  describe "a host's authorize that refuses" do
    test "save writes nothing and says so", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{authorize: denying(self())})
      select(view, "order_offer")

      html = save(view, %{subject: "Hacked"})

      assert html =~ @refused
      assert_received {:authorize, :save}
      assert subject_et(root) == "Pakkumine {{order_number}}\n"
      refute_received {:after_write, _paths}
      refute_received {:after_change, _name}
    end

    for action <- ["to_text", "md_to_html"] do
      test "#{action} converts nothing and says so", %{tmp_dir: root} do
        seed(root)
        test_pid = self()

        converter = fn _source ->
          send(test_pid, :converted)
          "converted"
        end

        view =
          mount_editor(root, %{
            authorize: denying(test_pid),
            convert: %{
              to_text: fn _format, source -> converter.(source) end,
              markdown_to_html: converter
            }
          })

        select(view, "order_offer")

        html = convert(view, unquote(action), %{markdown: "**Tere**"})

        assert html =~ @refused
        assert_received {:authorize, :convert}
        refute_received :converted
        assert field(view, :text) == "Tere!\n\n{{documents_list}}\n"
        assert field(view, :html) == ""
      end
    end

    test "create makes no draft and copies nothing", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{authorize: denying(self())})

      assert create(view, "order_new") =~ @refused
      assert_received {:authorize, :create}
      refute render(view) =~ "not saved yet"
      refute has_element?(view, "#editor-parts")

      assert create(view, "order_copy", "order_offer") =~ @refused
      refute File.exists?(Path.join(root, "order_copy"))
      refute_received {:after_write, _paths}
    end

    test "delete asks for no confirmation", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{authorize: denying(self())})
      select(view, "order_offer")

      assert view |> element("#editor-delete") |> render_click() =~ @refused
      assert_received {:authorize, :delete}
      refute has_element?(view, "#editor-delete-confirm")
    end

    test "confirm_delete deletes nothing, though delete was allowed", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{authorize: allowing(self())})
      select(view, "order_offer")
      view |> element("#editor-delete") |> render_click()
      assert has_element?(view, "#editor-delete-confirm")

      # The permission is taken away while the confirmation is open.
      send(view.pid, {:put, %{authorize: denying(self())}})

      assert view |> element("#editor-delete-confirm") |> render_click() =~ @refused
      assert File.dir?(Path.join(root, "order_offer"))
      refute has_element?(view, "#editor-delete-confirm")
      refute_received {:after_change, _name}
    end

    test "a raising authorize refuses and is logged", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{authorize: fn _action -> raise "permissions down" end})
      select(view, "order_offer")

      log = capture_log(fn -> assert save(view, %{subject: "Hacked"}) =~ @refused end)

      assert log =~ "authorize"
      assert log =~ "permissions down"
      assert subject_et(root) == "Pakkumine {{order_number}}\n"
      assert Process.alive?(view.pid)
    end

    test "anything but :ok refuses", %{tmp_dir: root} do
      seed(root)

      for answer <- [true, nil, {:ok, :yes}, :error] do
        view = mount_editor(root, %{authorize: fn _action -> answer end})
        select(view, "order_offer")

        assert save(view, %{subject: "Hacked"}) =~ @refused
        assert subject_et(root) == "Pakkumine {{order_number}}\n"
      end
    end

    test "an authorize that cannot be called refuses", %{tmp_dir: root} do
      seed(root)

      for authorize <- [fn -> :ok end, :yes, {Host, "preview"}] do
        view = mount_editor(root, %{authorize: authorize})
        select(view, "order_offer")

        assert save(view, %{subject: "Hacked"}) =~ @refused
        assert subject_et(root) == "Pakkumine {{order_number}}\n"
      end
    end
  end

  describe "a host's authorize that allows" do
    test "is asked on every change, and the change goes through", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{authorize: allowing(self()), convert: @convert})
      select(view, "order_offer")

      assert save(view, %{subject: "Uus"}) =~ "Saved."
      assert_received {:authorize, :save}
      assert subject_et(root) == "Uus"

      convert(view, "to_text", %{markdown: "**Tere**"})
      assert_received {:authorize, :convert}
      assert field(view, :text) == "Tere"

      create(view, "order_copy", "order_offer")
      assert_received {:authorize, :create}
      assert File.dir?(Path.join(root, "order_copy"))

      view |> element("#editor-delete") |> render_click()
      view |> element("#editor-delete-confirm") |> render_click()
      assert_received {:authorize, :delete}
      assert_received {:authorize, :delete}
      refute File.exists?(Path.join(root, "order_copy"))
    end

    test "{module, function} is called like a function", %{tmp_dir: root} do
      seed(root)
      view = mount_editor(root, %{authorize: {__MODULE__.Allow, :authorize}})
      select(view, "order_offer")

      assert save(view, %{subject: "Uus"}) =~ "Saved."
      assert subject_et(root) == "Uus"
    end
  end

  describe "editable" do
    test "anything but true is read-only, and forged events are refused with a notice",
         %{tmp_dir: root} do
      seed(root)

      for editable <- ["true", 1, :yes, nil] do
        view = mount_editor(root, %{editable: editable, authorize: allowing(self())})
        select(view, "order_offer")
        target = with_target(view, "#editor")

        refute has_element?(view, "#editor-parts")
        refute has_element?(view, "#editor-create")

        assert render_submit(target, "save", %{"parts" => %{"subject" => "Hacked"}}) =~
                 @read_only

        assert render_submit(target, "save", %{
                 "action" => "to_text",
                 "parts" => %{"markdown" => "**x**"}
               }) =~ @read_only

        assert render_submit(target, "create", %{
                 "create" => %{"name" => "order_x", "copy_from" => "order_offer"}
               }) =~ @read_only

        assert render_click(target, "delete", %{}) =~ @read_only
        assert render_click(target, "confirm_delete", %{}) =~ @read_only

        assert subject_et(root) == "Pakkumine {{order_number}}\n"
        refute File.exists?(Path.join(root, "order_x"))
        assert File.dir?(Path.join(root, "order_offer"))
      end

      # Read-only is decided before the host is asked.
      refute_received {:authorize, _action}
    end
  end

  defmodule Allow do
    @moduledoc false
    def authorize(_action), do: :ok
  end
end
