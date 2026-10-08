defmodule PhoenixKitTemplatesEditor.FilesTest do
  # Not async: `reload/1` and the core-path tests change
  # `config :phoenix_kit, :template_paths`, and `uncommitted/1` tests set
  # `GIT_*` variables of the VM.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias PhoenixKit.Templates
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Files

  @moduletag :tmp_dir

  defp put(root, name, file, content) do
    File.mkdir_p!(Path.join(root, name))
    path = Path.join([root, name, file])
    File.write!(path, content)
    path
  end

  defp subject(root, name \\ "order_x"),
    do: Templates.render(name, %{}, %{}, locale: "et", paths: [root]).subject

  defp core_paths(paths) do
    previous = Application.fetch_env(:phoenix_kit, :template_paths)
    Application.put_env(:phoenix_kit, :template_paths, paths)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:phoenix_kit, :template_paths, value)
        :error -> Application.delete_env(:phoenix_kit, :template_paths)
      end

      Overrides.reset_cache(paths)
    end)
  end

  defp mode(path), do: Bitwise.band(File.lstat!(path).mode, 0o7777)

  describe "realpath/1 and same_dir?/2" do
    test "a link to a directory resolves to the directory", %{tmp_dir: tmp} do
      dir = Path.join(tmp, "real")
      File.mkdir_p!(Path.join(dir, "inner"))
      link = Path.join(tmp, "link")
      File.ln_s!(dir, link)

      assert Files.realpath(link) == {:ok, dir}
      assert Files.realpath(Path.join(link, "inner")) == {:ok, Path.join(dir, "inner")}
      assert Files.same_dir?(link, dir)
      assert Files.same_dir?(dir <> "/inner/..", dir)
      refute Files.same_dir?(link, Path.join(dir, "inner"))
    end

    test "a relative link, a chain of links, and a missing path", %{tmp_dir: tmp} do
      File.mkdir_p!(Path.join(tmp, "a/b"))
      File.ln_s!("a/b", Path.join(tmp, "one"))
      File.ln_s!(Path.join(tmp, "one"), Path.join(tmp, "two"))

      assert Files.realpath(Path.join(tmp, "two")) == {:ok, Path.join(tmp, "a/b")}
      assert {:error, :enoent} = Files.realpath(Path.join(tmp, "missing/x"))
      refute Files.same_dir?(Path.join(tmp, "missing"), Path.join(tmp, "missing"))
    end

    test "a loop of links is an error, not a hang", %{tmp_dir: tmp} do
      File.ln_s!(Path.join(tmp, "y"), Path.join(tmp, "x"))
      File.ln_s!(Path.join(tmp, "x"), Path.join(tmp, "y"))

      assert {:error, :eloop} = Files.realpath(Path.join(tmp, "x"))
    end
  end

  describe "reload/1" do
    test "drops the cached lookups of the root", %{tmp_dir: root} do
      path = put(root, "order_x", "subject.et.txt", "Old")
      assert subject(root) == "Old"

      File.write!(path, "New")
      assert subject(root) == "Old"

      assert Files.reload(root) == :ok
      assert subject(root) == "New"
    end

    test "and those under core's path string for the same directory", %{tmp_dir: tmp} do
      root = Path.join(tmp, "templates")
      File.mkdir_p!(root)
      core = Path.join(tmp, "build_link")
      File.ln_s!(root, core)
      core_paths([core])

      path = put(root, "order_x", "subject.et.txt", "Old")
      assert {subject(root), subject(core)} == {"Old", "Old"}

      File.write!(path, "New")
      Files.reload(root)

      assert {subject(root), subject(core)} == {"New", "New"}
    end

    test "but not another directory's", %{tmp_dir: tmp} do
      root = Path.join(tmp, "templates")
      other = Path.join(tmp, "other")
      File.mkdir_p!(root)
      core_paths([other])

      path = put(other, "order_x", "subject.et.txt", "Old")
      assert subject(other) == "Old"
      File.write!(path, "New")

      Files.reload(root)
      assert subject(other) == "Old"
    end
  end

  describe "after_write/2" do
    # Modes are the umask's and the root's setgid bit's (README,
    # installation): changing them afterwards, as the server's user, in a
    # directory others may write to, would follow a link put there in the
    # meantime (spec §12 item 5).
    test "leaves the modes as the write made them, drops the cache", %{tmp_dir: root} do
      put(root, "order_x", "subject.et.txt", "Old")
      assert subject(root) == "Old"

      {:ok, paths} = Overrides.write(root, "order_x", :subject, "et", "New")
      [file] = paths
      File.chmod!(file, 0o600)

      assert Files.after_write(root, paths) == :ok

      assert mode(file) == 0o600
      assert subject(root) == "New"
    end

    test "a written file is readable at once through core's path string", %{tmp_dir: tmp} do
      root = Path.join(tmp, "templates")
      File.mkdir_p!(root)
      core = Path.join(tmp, "build_link")
      File.ln_s!(root, core)
      core_paths([core])

      put(root, "order_x", "subject.et.txt", "Old")
      assert subject(core) == "Old"

      {:ok, paths} = Overrides.write(root, "order_x", :subject, "et", "New")
      Files.after_write(root, paths)

      assert subject(core) == "New"
    end

    test "a symbolic link is left alone, not followed", %{tmp_dir: tmp} do
      root = Path.join(tmp, "templates")
      File.mkdir_p!(Path.join(root, "order_x"))
      outside = Path.join(tmp, "outside.txt")
      File.write!(outside, "secret")
      File.chmod!(outside, 0o600)
      link = Path.join([root, "order_x", "text.txt"])
      File.ln_s!(outside, link)

      assert Files.after_write(root, [link]) == :ok
      assert mode(outside) == 0o600
    end

    test "a path already gone: the cache is dropped all the same", %{tmp_dir: root} do
      path = put(root, "order_x", "subject.et.txt", "Old")
      assert subject(root) == "Old"
      File.write!(path, "New")

      assert Files.after_write(root, [Path.join([root, "order_x", "text.et.txt"])]) == :ok
      assert subject(root) == "New"
    end
  end

  describe "uncommitted/1" do
    # A repository holding the root as priv/templates beside a file of its
    # own, everything committed.
    defp repo!(tmp) do
      repo = Path.join(tmp, "repo")
      root = Path.join(repo, "priv/templates")
      put(root, "order_offer", "subject.et.txt", "Offer")
      put(root, "order_offer", "text.et.txt", "Hello")
      File.write!(Path.join(repo, "README"), "repo")
      git!(repo, ["init", "-q"])
      git!(repo, ["add", "."])
      git!(repo, ["commit", "-q", "--no-verify", "-m", "init"])
      {repo, root}
    end

    defp git!(repo, args) do
      identity = ["-c", "user.name=Test", "-c", "user.email=test@example.com"]
      {_out, 0} = System.cmd("git", identity ++ ["-c", "commit.gpgsign=false" | args], cd: repo)
    end

    defp with_env(vars) do
      previous = for {key, _value} <- vars, do: {key, System.get_env(key)}
      Enum.each(vars, fn {key, value} -> System.put_env(key, value) end)

      on_exit(fn ->
        Enum.each(previous, fn
          {key, nil} -> System.delete_env(key)
          {key, value} -> System.put_env(key, value)
        end)
      end)
    end

    test "a committed tree: nothing", %{tmp_dir: tmp} do
      {_repo, root} = repo!(tmp)
      assert Files.uncommitted(root) == []
    end

    test "changed, new and deleted files under the root, by their path in the repository",
         %{tmp_dir: tmp} do
      {repo, root} = repo!(tmp)

      File.write!(Path.join([root, "order_offer", "text.et.txt"]), "New text")
      File.rm!(Path.join([root, "order_offer", "subject.et.txt"]))
      put(root, "order_test", "subject.et.txt", "Test")
      File.write!(Path.join(repo, "README"), "changed outside the root")

      assert Files.uncommitted(root) == [
               "priv/templates/order_offer/subject.et.txt",
               "priv/templates/order_offer/text.et.txt",
               "priv/templates/order_test/subject.et.txt"
             ]
    end

    test "leaves git's index alone", %{tmp_dir: tmp} do
      {repo, root} = repo!(tmp)
      index = Path.join([repo, ".git", "index"])
      %File.Stat{inode: inode} = File.stat!(index)

      File.touch!(
        Path.join([root, "order_offer", "text.et.txt"]),
        System.os_time(:second) + 3600
      )

      assert Files.uncommitted(root) == []
      assert %File.Stat{inode: ^inode} = File.stat!(index)
    end

    test "runs no fsmonitor hook the repository configures", %{tmp_dir: tmp} do
      {repo, root} = repo!(tmp)
      marker = Path.join(tmp, "fsmonitor-ran")
      hook = Path.join(tmp, "hook.sh")
      File.write!(hook, "#!/bin/sh\ntouch #{marker}\n")
      File.chmod!(hook, 0o755)
      git!(repo, ["config", "core.fsmonitor", hook])

      File.write!(Path.join([root, "order_offer", "text.et.txt"]), "New text")

      assert Files.uncommitted(root) == ["priv/templates/order_offer/text.et.txt"]
      refute File.exists?(marker)
    end

    # A filter driver is a command the repository's config names, run by
    # `git status` on every file whose stat changed (spec §12 item 6): the
    # repository's owner must not run commands as the server's user.
    test "runs no filter driver the repository configures", %{tmp_dir: tmp} do
      {repo, root} = repo!(tmp)
      log = Path.join(tmp, "filter-ran")

      File.write!(Path.join(repo, ".gitattributes"), "*.txt filter=evil\n*.html filter=proc\n")
      put(root, "order_offer", "html.et.html", "<p>Hi</p>")
      git!(repo, ["add", "."])
      git!(repo, ["commit", "-q", "--no-verify", "-m", "attributes"])

      git!(repo, ["config", "filter.evil.clean", "sh -c 'echo clean >> #{log}; cat'"])
      git!(repo, ["config", "filter.proc.process", "sh -c 'echo process >> #{log}; exit 1'"])
      git!(repo, ["config", "filter.ev.il.clean", "sh -c 'echo dotted >> #{log}; cat'"])

      later = System.os_time(:second) + 3600
      File.touch!(Path.join([root, "order_offer", "text.et.txt"]), later)
      File.touch!(Path.join([root, "order_offer", "html.et.html"]), later)
      File.write!(Path.join([root, "order_offer", "subject.et.txt"]), "Changed")

      assert Files.uncommitted(root) == ["priv/templates/order_offer/subject.et.txt"]
      refute File.exists?(log)
    end

    test "a filter driver whose name git's -c cannot carry: nothing asked", %{tmp_dir: tmp} do
      {repo, root} = repo!(tmp)
      log = Path.join(tmp, "filter-ran")
      File.write!(Path.join(repo, ".gitattributes"), "*.txt filter=a=b\n")
      git!(repo, ["config", "filter.a=b.clean", "sh -c 'echo ran >> #{log}; cat'"])
      File.write!(Path.join([root, "order_offer", "subject.et.txt"]), "Changed")
      Logger.put_module_level(Files, :warning)
      on_exit(fn -> Logger.delete_module_level(Files) end)

      assert capture_log([level: :warning], fn -> assert Files.uncommitted(root) == [] end) =~
               "filter"

      refute File.exists?(log)
    end

    test "ignores GIT_* variables of the server's environment", %{tmp_dir: tmp} do
      {_repo, root} = repo!(tmp)
      {other_repo, _other_root} = repo!(Path.join(tmp, "other"))
      File.write!(Path.join([root, "order_offer", "text.et.txt"]), "New text")

      with_env([
        {"GIT_DIR", Path.join(other_repo, ".git")},
        {"GIT_WORK_TREE", other_repo}
      ])

      assert Files.uncommitted(root) == ["priv/templates/order_offer/text.et.txt"]
    end

    test "a root outside any repository: nothing", %{tmp_dir: tmp} do
      root = Path.join(tmp, "plain")
      put(root, "order_offer", "subject.et.txt", "Offer")
      with_env([{"GIT_CEILING_DIRECTORIES", tmp}])

      assert Files.uncommitted(root) == []
    end

    test "no root on disk: nothing", %{tmp_dir: tmp} do
      assert Files.uncommitted(Path.join(tmp, "missing")) == []
    end
  end

  describe "safe_read/2" do
    test "a regular file inside the root", %{tmp_dir: root} do
      path = put(root, "order_x", "text.txt", "Hello")
      assert Files.safe_read(root, path) == {:ok, "Hello"}
    end

    test "a symbolic link is refused, even one to a file inside the root", %{tmp_dir: root} do
      target = put(root, "order_x", "text.txt", "Hello")
      link = Path.join([root, "order_x", "text.et.txt"])
      File.ln_s!(target, link)

      assert Files.safe_read(root, link) == {:error, :unsafe_path}
    end

    test "a file under a linked directory leading out of the root is refused", %{tmp_dir: tmp} do
      root = Path.join(tmp, "templates")
      File.mkdir_p!(root)
      outside = Path.join(tmp, "secrets")
      put(outside, ".", "text.txt", "secret")
      File.ln_s!(outside, Path.join(root, "order_x"))

      assert Files.safe_read(root, Path.join([root, "order_x", "text.txt"])) ==
               {:error, :unsafe_path}
    end

    test "a path outside the root, or climbing out of it, is refused", %{tmp_dir: tmp} do
      root = Path.join(tmp, "templates")
      File.mkdir_p!(root)
      outside = put(tmp, "other", "text.txt", "secret")

      assert Files.safe_read(root, outside) == {:error, :unsafe_path}
      assert Files.safe_read(root, Path.join(root, "../other/text.txt")) == {:error, :unsafe_path}
      assert Files.safe_read(root, root <> "x/text.txt") == {:error, :unsafe_path}
    end

    test "a root reached through a link reads its own files", %{tmp_dir: tmp} do
      real = Path.join(tmp, "real")
      put(real, "order_x", "text.txt", "Hello")
      link = Path.join(tmp, "link")
      File.ln_s!(real, link)

      assert Files.safe_read(link, Path.join([link, "order_x", "text.txt"])) == {:ok, "Hello"}
    end

    test "a file larger than the library writes is refused", %{tmp_dir: root} do
      path = put(root, "order_x", "html.html", String.duplicate("x", Overrides.max_bytes() + 1))
      assert Files.safe_read(root, path) == {:error, :too_large}
    end

    test "a missing file, a directory", %{tmp_dir: root} do
      File.mkdir_p!(Path.join(root, "order_x"))

      assert Files.safe_read(root, Path.join([root, "order_x", "text.txt"])) == {:error, :enoent}
      assert Files.safe_read(root, Path.join(root, "order_x")) == {:error, :unsafe_path}
    end
  end

  describe "check_template/2" do
    test "a template whose files are all plain: :ok; no such template: :ok", %{tmp_dir: root} do
      put(root, "order_x", "subject.et.txt", "Hi")
      put(root, "order_x", "audience.txt", "partner")
      File.mkdir_p!(Path.join([root, "order_x", "sub"]))

      assert Files.check_template(root, "order_x") == :ok
      assert Files.check_template(root, "order_missing") == :ok
    end

    test "a link among its files, even to a file inside the root: refused", %{tmp_dir: root} do
      put(root, "order_x", "notes.txt", "inside")
      File.ln_s!("notes.txt", Path.join([root, "order_x", "text.et.txt"]))

      assert Files.check_template(root, "order_x") ==
               {:error, {:unsafe_path, Path.join([root, "order_x", "text.et.txt"])}}
    end

    test "a hidden file is not looked at: nothing reads it", %{tmp_dir: root} do
      put(root, "order_x", "subject.et.txt", "Hi")
      File.ln_s!("/etc/hostname", Path.join([root, "order_x", ".subject.et.txt.tmp"]))

      assert Files.check_template(root, "order_x") == :ok
    end

    test "a template directory that is a link, or not a directory: refused", %{tmp_dir: tmp} do
      root = Path.join(tmp, "templates")
      outside = Path.join(tmp, "outside")
      put(outside, "order_x", "subject.et.txt", "Hi")
      File.mkdir_p!(root)
      File.ln_s!(Path.join(outside, "order_x"), Path.join(root, "order_x"))
      File.write!(Path.join(root, "order_file"), "x")

      assert {:error, {:unsafe_path, _path}} = Files.check_template(root, "order_x")
      assert {:error, {:unsafe_path, _path}} = Files.check_template(root, "order_file")
    end

    test "a name that is not one template directory: refused", %{tmp_dir: root} do
      assert {:error, {:unsafe_path, _path}} = Files.check_template(root, "../x")
      assert {:error, {:unsafe_path, _path}} = Files.check_template(root, "a/b")
    end

    test "a named pipe among its files: refused, never opened", %{tmp_dir: root} do
      put(root, "order_x", "subject.et.txt", "Hi")
      {_out, 0} = System.cmd("mkfifo", [Path.join([root, "order_x", "text.et.txt"])])

      assert {:error, {:unsafe_path, _path}} = Files.check_template(root, "order_x")
    end
  end

  describe "check_template_dir/2" do
    test "a missing template or a real directory: :ok", %{tmp_dir: root} do
      put(root, "order_x", "notes.txt", "inside")
      File.ln_s!("notes.txt", Path.join([root, "order_x", "text.et.txt"]))

      assert Files.check_template_dir(root, "order_x") == :ok
      assert Files.check_template_dir(root, "order_new") == :ok
    end

    test "a template directory that is a link, even inside the root: refused", %{tmp_dir: root} do
      put(root, "order_x", "subject.et.txt", "Hi")
      File.ln_s!("order_x", Path.join(root, "order_y"))

      assert {:error, {:unsafe_path, _path}} = Files.check_template_dir(root, "order_y")
      assert {:error, {:unsafe_path, _path}} = Files.check_template_dir(root, "..")
    end
  end

  describe "usage/1" do
    test "the templates and the bytes of their files and the root's own", %{tmp_dir: root} do
      put(root, "order_x", "subject.et.txt", "12345")
      put(root, "order_y", "text.et.txt", "123")
      File.mkdir_p!(Path.join(root, ".order_z.tmp"))
      File.write!(Path.join(root, "README.md"), "12")

      assert Files.usage(root) == %{templates: 2, bytes: 10}
    end

    test "no root: nothing", %{tmp_dir: tmp} do
      assert Files.usage(Path.join(tmp, "missing")) == %{templates: 0, bytes: 0}
    end
  end

  describe "relative/2" do
    test "a path under the root, as the root sees it; anything else by its base name",
         %{tmp_dir: root} do
      assert Files.relative(root, Path.join([root, "order_x", "text.txt"])) == "order_x/text.txt"
      assert Files.relative(root, "/etc/passwd") == "passwd"
    end
  end

  describe "host_files/2" do
    test "the regular files a copy takes that are not template parts", %{tmp_dir: tmp} do
      root = Path.join(tmp, "root")
      put(root, "order_x", "subject.et.txt", "S")
      put(root, "order_x", "layout.txt", "shop")
      put(root, "order_x", "audience.txt", "partner")
      put(root, "order_x", "notes.md", "n")
      put(root, "order_x", ".tmp-write", "half")
      File.mkdir_p!(Path.join([root, "order_x", "sub"]))
      File.write!(Path.join(tmp, "outside.txt"), "secret")
      File.ln_s!(Path.join(tmp, "outside.txt"), Path.join([root, "order_x", "link.txt"]))

      assert Files.host_files(root, "order_x") == ["audience.txt", "notes.md"]
    end

    test "nothing for a missing template or a bad name", %{tmp_dir: root} do
      assert Files.host_files(root, "order_none") == []
      assert Files.host_files(root, "../etc") == []
    end
  end
end
