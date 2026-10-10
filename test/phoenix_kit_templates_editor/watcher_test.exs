defmodule PhoenixKitTemplatesEditor.WatcherTest do
  # Where the templates are edited (`editable: true`, or `watch: true`), a
  # change of the files on disk — a hand edit, a `git pull` — reaches the
  # next email without a restart: every 2 s the watcher
  # compares the root's files (name, mtime, size) with its last look and, on
  # a difference, drops the cached lookups (`Files.reload/1`) and says so on
  # PubSub. Elsewhere it does not run. The comparison, `check/2`, is called
  # directly here: no waiting on timers.
  #
  # Not async: it changes `config :phoenix_kit_templates_editor` and core's
  # template paths.
  use ExUnit.Case, async: false

  alias PhoenixKit.PubSub.Manager, as: PubSub
  alias PhoenixKit.Templates
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Watcher

  @moduletag :tmp_dir

  setup do
    previous = Application.get_all_env(:phoenix_kit_templates_editor)

    on_exit(fn ->
      for {key, _} <- Application.get_all_env(:phoenix_kit_templates_editor),
          do: Application.delete_env(:phoenix_kit_templates_editor, key)

      for {key, value} <- previous,
          do: Application.put_env(:phoenix_kit_templates_editor, key, value)
    end)
  end

  defp config(values) do
    for {key, value} <- values, do: Application.put_env(:phoenix_kit_templates_editor, key, value)
  end

  defp put(root, name, file, content) do
    File.mkdir_p!(Path.join(root, name))
    path = Path.join([root, name, file])
    File.write!(path, content)
    path
  end

  defp subject(root),
    do: Templates.render("order_x", %{}, %{}, locale: "et", paths: [root]).subject

  defp core_link!(tmp, root) do
    core = Path.join(tmp, "build_link")
    File.ln_s!(root, core)
    previous = Application.fetch_env(:phoenix_kit, :template_paths)
    Application.put_env(:phoenix_kit, :template_paths, [core])

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:phoenix_kit, :template_paths, value)
        :error -> Application.delete_env(:phoenix_kit, :template_paths)
      end

      Overrides.reset_cache([core])
    end)

    core
  end

  describe "where it runs" do
    test "not unless editable is exactly true or watch is true", %{tmp_dir: root} do
      for values <- [
            [editable: false],
            [editable: "true"],
            [editable: true, watch: false],
            [editable: false, watch: false]
          ] do
        for key <- [:editable, :watch],
            do: Application.delete_env(:phoenix_kit_templates_editor, key)

        config([root: root] ++ values)
        assert Watcher.init([]) == :ignore, inspect(values)
      end
    end

    test "not with a root that does not exist", %{tmp_dir: tmp} do
      config(root: Path.join(tmp, "missing"), editable: true)
      assert Watcher.init([]) == :ignore
    end

    test "where the files are edited, or watched: its first look taken", %{tmp_dir: root} do
      put(root, "order_x", "subject.et.txt", "Old")

      for values <- [[editable: true], [editable: false, watch: true]] do
        for key <- [:editable, :watch],
            do: Application.delete_env(:phoenix_kit_templates_editor, key)

        config([root: root] ++ values)

        pid = start_supervised!(Watcher)
        assert %{root: ^root, snapshot: snapshot} = :sys.get_state(pid)
        assert snapshot == Watcher.snapshot(root)
        stop_supervised!(Watcher)
      end
    end

    test "is one of the module's children" do
      assert Watcher in PhoenixKitTemplatesEditor.children()
    end
  end

  describe "check/2" do
    test "a file changed on disk: the cached lookups go under both paths, and it is said",
         %{tmp_dir: tmp} do
      root = Path.join(tmp, "templates")
      path = put(root, "order_x", "subject.et.txt", "Old")
      core = core_link!(tmp, root)
      PubSub.subscribe(Watcher.topic())

      before = Watcher.snapshot(root)
      assert {subject(root), subject(core)} == {"Old", "Old"}

      File.write!(path, "Newer")

      assert Watcher.check(root, before) != before
      assert {subject(root), subject(core)} == {"Newer", "Newer"}
      assert_receive {:templates_editor, :files_changed}
    end

    test "nothing changed: the same look back, the cache kept", %{tmp_dir: root} do
      path = put(root, "order_x", "subject.et.txt", "Old")
      %File.Stat{mtime: mtime} = File.stat!(path, time: :posix)
      before = Watcher.snapshot(root)
      assert subject(root) == "Old"

      # Same size, same mtime: not a change the watcher sees, so the cache
      # (still "Old") shows that it dropped nothing.
      File.write!(path, "New")
      File.touch!(path, mtime)

      assert Watcher.check(root, before) == before
      assert subject(root) == "Old"
    end

    test "a new file, a removed one, a new template, a file in the root itself",
         %{tmp_dir: root} do
      put(root, "order_x", "subject.et.txt", "Old")

      changes = [
        fn -> put(root, "order_x", "text.et.txt", "Text") end,
        fn -> File.rm!(Path.join([root, "order_x", "text.et.txt"])) end,
        fn -> put(root, "order_y", "subject.et.txt", "Y") end,
        fn -> File.write!(Path.join(root, "README.md"), "# Notes") end
      ]

      Enum.reduce(changes, Watcher.snapshot(root), fn change, before ->
        change.()
        after_change = Watcher.check(root, before)
        assert after_change != before
        after_change
      end)
    end

    test "links are looked at, not followed", %{tmp_dir: tmp} do
      root = Path.join(tmp, "templates")
      File.mkdir_p!(root)
      outside = Path.join(tmp, "outside")
      put(outside, "order_x", "subject.et.txt", "Outside")
      File.ln_s!(Path.join(outside, "order_x"), Path.join(root, "order_x"))

      assert [{"order_x", _mtime, _size}] = Watcher.snapshot(root)
    end

    test "no root: an empty look, no error", %{tmp_dir: tmp} do
      root = Path.join(tmp, "missing")

      assert Watcher.snapshot(root) == []
      assert Watcher.check(root, []) == []
    end
  end
end
