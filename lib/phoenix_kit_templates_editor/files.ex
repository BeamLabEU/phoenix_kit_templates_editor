defmodule PhoenixKitTemplatesEditor.Files do
  @moduledoc """
  The template files on disk, around what `PhoenixKit.Templates.Overrides`
  already does: dropping the renderer's cache, settling what a write
  created, asking git what is not committed, and reading a file only when it
  is what it claims to be.

  Every message here names a file relative to the root, never by its
  absolute path.
  """

  require Logger

  alias PhoenixKit.Email.Content
  alias PhoenixKit.Templates.Overrides
  alias PhoenixKitTemplatesEditor.Bounded

  @max_links 40
  @git_timeout 5_000
  # More filter drivers than this in one repository's config is no setup a
  # person made: git is not asked at all.
  @max_filters 100

  @doc """
  Drops the cached lookups of the files under `root` — after they changed
  on disk (the editor, a hand edit, a `git pull`) — so the next email reads
  them again.

  The cache of `Overrides` is keyed on the path *string* it was read by.
  Core reads by its own (`PhoenixKit.Email.Content.override_paths/0`), which
  may name the same directory differently (a link under `_build`); every
  core path that is the same directory as `root` (`same_dir?/2`) is dropped
  too.
  """
  @spec reload(Path.t()) :: :ok
  def reload(root) when is_binary(root) do
    Overrides.reset_cache(Enum.uniq([root | core_paths_for(root)]))
  end

  defp core_paths_for(root) do
    Enum.filter(Content.override_paths(), &(is_binary(&1) and same_dir?(&1, root)))
  rescue
    _ -> []
  end

  @doc """
  What the editor calls after it wrote `paths` under `root`: `reload/1`.

  Neither the mode nor the owner of what was written is changed: changing
  them afterwards, as the server's user, in a directory others may write to,
  would follow a link put there in the meantime (spec §12 item 5). They come
  from the server's umask and the root's setgid bit instead — `umask 0002`
  and a setgid root of the tree owner's group make new files `0664` and new
  directories `2775` of that group (README, installation).
  """
  @spec after_write(Path.t(), [Path.t()]) :: :ok
  def after_write(root, paths) when is_binary(root) and is_list(paths), do: reload(root)

  @doc """
  The files under `root` that differ from git's last commit — changed, new
  or deleted — by their paths in the repository, sorted: a change made in
  the editor reaches another server only once it is committed.

  Asked as `git -c core.fsmonitor=false <filters> --no-optional-locks status
  --porcelain=v1 -z --untracked-files=all --no-renames --ignore-submodules=all
  -- .` in `root`. Nothing the repository's config names runs as the
  server's user (spec §12 item 6): no fsmonitor hook, and no filter driver —
  `<filters>` sets the `clean`, `smudge` and `process` command of every
  driver the config defines (`git config --get-regexp`, which only reads) to
  nothing; a driver name `-c` cannot carry, or more than #{@max_filters} of
  them, and git is not asked at all. git never rewrites the index (the
  server may run as another user than the tree's owner), never fetches a
  missing object, and no `GIT_*` variable of the server's environment
  points it elsewhere. Each git command is killed after
  #{div(@git_timeout, 1000)} s (`timeout`, where installed). `[]` when the
  root is not in a git work tree, git is not installed, or it does not
  answer in time.
  """
  @spec uncommitted(Path.t()) :: [String.t()]
  def uncommitted(root) when is_binary(root) do
    with true <- File.dir?(root),
         git when is_binary(git) <- System.find_executable("git"),
         {:ok, {:ok, output}} <-
           Bounded.run(fn -> git_status(git, root) end, @git_timeout * 2 + 1_000) do
      output |> String.split(<<0>>, trim: true) |> Enum.flat_map(&status_path/1) |> Enum.sort()
    else
      {:error, :timeout} ->
        Logger.warning("[PhoenixKitTemplatesEditor] git status did not answer in time")
        []

      {:ok, {:error, :unsafe_filters}} ->
        Logger.warning(
          "[PhoenixKitTemplatesEditor] git status not asked: the repository's filter drivers cannot be switched off"
        )

        []

      _no_status ->
        []
    end
  end

  defp git_status(git, root) do
    with {:ok, filters} <- neutral_filters(git, root),
         {output, 0} <-
           run_git(
             git,
             root,
             ~w(-c core.fsmonitor=false) ++
               filters ++
               ~w(--no-optional-locks status --porcelain=v1 -z --untracked-files=all) ++
               ~w(--no-renames --ignore-submodules=all -- .)
           ) do
      {:ok, output}
    else
      {:error, reason} -> {:error, reason}
      {_output, _status} -> {:error, :git}
    end
  end

  # `-c filter.<name>.<command>=` for every driver the config defines:
  # an empty command is no command.
  defp neutral_filters(git, root) do
    case run_git(git, root, ~w(config -z --get-regexp ^filter\.)) do
      {output, 0} -> output |> filter_names() |> filter_options()
      {_none, 1} -> {:ok, []}
      {_output, _status} -> {:error, :git}
    end
  end

  # `-z`: each entry is `<key>\n<value>\0`; the key `filter.<name>.<var>`.
  defp filter_names(output) do
    for entry <- String.split(output, <<0>>, trim: true),
        [key | _value] = String.split(entry, "\n", parts: 2),
        "filter." <> rest = key,
        {name, _var} = rest |> String.split(".") |> Enum.split(-1),
        uniq: true,
        do: Enum.join(name, ".")
  end

  defp filter_options(names) do
    if length(names) > @max_filters or Enum.any?(names, &(&1 == "" or &1 =~ ~r/[=\n]/)) do
      {:error, :unsafe_filters}
    else
      {:ok,
       for(
         name <- names,
         command <- ~w(clean smudge process),
         do: ["-c", "filter.#{name}.#{command}="]
       )
       |> List.flatten()}
    end
  end

  defp run_git(git, root, args) do
    {command, args} =
      case System.find_executable("timeout") do
        nil -> {git, args}
        timeout -> {timeout, ["-s", "KILL", "#{div(@git_timeout, 1000)}", git | args]}
      end

    System.cmd(command, args, cd: root, env: git_env(), stderr_to_stdout: false)
  end

  defp git_env do
    cleared =
      for {name, _value} <- System.get_env(), String.starts_with?(name, "GIT_"), do: {name, nil}

    cleared ++ [{"GIT_NO_LAZY_FETCH", "1"}]
  end

  # `XY path`, one per entry of `--porcelain=v1 -z`; with `--no-renames` no
  # entry carries a second path.
  defp status_path(<<_x, _y, ?\s, path::binary>>), do: [path]
  defp status_path(_other), do: []

  @doc """
  Reads the template file `path` under `root` — the check every read of a
  template file goes through.

  Refused with `{:error, :unsafe_path}`: a path not under `root`, a
  symbolic link (even one to a file inside the root), anything but a
  regular file, and a file whose real location (`realpath/1`, through
  linked directories) is outside the root's. A file over
  `PhoenixKit.Templates.Overrides.max_bytes/0` is `{:error, :too_large}`;
  a missing one `{:error, :enoent}`.
  """
  @spec safe_read(Path.t(), Path.t()) :: {:ok, binary()} | {:error, atom()}
  def safe_read(root, path) when is_binary(root) and is_binary(path) do
    with {:ok, %File.Stat{size: size}} <- check(root, path) do
      if size > Overrides.max_bytes(),
        do: {:error, :too_large},
        else: File.read(Path.expand(path))
    end
  end

  @doc """
  The checks of `safe_read/2` without the read: `{:ok, stat}` for a regular
  file inside `root`, else the error `safe_read/2` would give (but for the
  size).
  """
  @spec check(Path.t(), Path.t()) :: {:ok, File.Stat.t()} | {:error, atom()}
  def check(root, path) when is_binary(root) and is_binary(path) do
    root = Path.expand(root)
    path = Path.expand(path)

    with true <- String.starts_with?(path, root <> "/") || {:error, :unsafe_path},
         {:ok, %File.Stat{type: :regular} = stat} <- lstat(path),
         {:ok, real_root} <- realpath(root),
         {:ok, real_path} <- realpath(path),
         true <- String.starts_with?(real_path, real_root <> "/") || {:error, :unsafe_path} do
      {:ok, stat}
    else
      {:ok, %File.Stat{}} -> {:error, :unsafe_path}
      {:error, :eloop} -> {:error, :unsafe_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp lstat(path), do: File.lstat(path)

  @doc """
  Checks template `name` under `root` before anything in it is read, even
  through `PhoenixKit.Templates.Overrides.locate/4` (which reads by
  following links, and keeps what it read in its cache): `:ok` when there is
  no such template, or when it is a real directory inside the root (not a
  link, `check_template_dir/2`) holding only regular files and directories
  — a link (even to a file inside the root), a pipe or a device among its
  files is `{:error, {:unsafe_path, path}}`. Hidden files are not looked
  at: nothing reads them.
  """
  @spec check_template(Path.t(), String.t()) :: :ok | {:error, {:unsafe_path, Path.t()}}
  def check_template(root, name) when is_binary(root) and is_binary(name) do
    dir = Path.join(Path.expand(root), name)

    with :ok <- check_template_dir(root, name),
         {:ok, entries} <- File.ls(dir) do
      entries
      |> Enum.reject(&String.starts_with?(&1, "."))
      |> Enum.map(&Path.join(dir, &1))
      |> Enum.find(&(not plain?(&1)))
      |> case do
        nil -> :ok
        path -> {:error, {:unsafe_path, path}}
      end
    else
      {:error, :enoent} -> :ok
      {:error, {:unsafe_path, _path}} = error -> error
      {:error, _reason} -> {:error, {:unsafe_path, dir}}
    end
  end

  defp plain?(path),
    do:
      match?({:ok, %File.Stat{type: type}} when type in [:regular, :directory], File.lstat(path))

  @doc """
  Checks the directory of template `name` under `root` before anything is
  written into it: `:ok` when it does not exist yet, or is a real directory
  directly inside the root — not a link, even to another template, so a
  write cannot land anywhere else. Else `{:error, {:unsafe_path, path}}`.
  """
  @spec check_template_dir(Path.t(), String.t()) :: :ok | {:error, {:unsafe_path, Path.t()}}
  def check_template_dir(root, name) when is_binary(root) and is_binary(name) do
    root = Path.expand(root)
    dir = Path.join(root, name)

    with true <- Overrides.valid_name?(name) || {:error, {:unsafe_path, dir}},
         {:ok, %File.Stat{type: :directory}} <- File.lstat(dir),
         {:ok, real_root} <- realpath(root),
         {:ok, real_dir} <- realpath(dir),
         true <- real_dir == Path.join(real_root, name) || {:error, {:unsafe_path, dir}} do
      :ok
    else
      {:error, :enoent} -> :ok
      {:error, {:unsafe_path, _path}} = error -> error
      _other -> {:error, {:unsafe_path, dir}}
    end
  end

  @doc """
  How much `root` holds: `templates`, the template directories in it (a
  name `PhoenixKit.Templates.Overrides` takes), and `bytes`, the sizes of
  the regular files in the root and directly in its directories. Links are
  not followed. `%{templates: 0, bytes: 0}` for a missing root.
  """
  @spec usage(Path.t()) :: %{templates: non_neg_integer(), bytes: non_neg_integer()}
  def usage(root) when is_binary(root) do
    case File.ls(root) do
      {:ok, entries} ->
        Enum.reduce(entries, %{templates: 0, bytes: 0}, &add_usage(root, &1, &2))

      {:error, _reason} ->
        %{templates: 0, bytes: 0}
    end
  end

  defp add_usage(root, entry, acc) do
    path = Path.join(root, entry)

    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} ->
        templates = if Overrides.valid_name?(entry), do: 1, else: 0
        %{acc | templates: acc.templates + templates, bytes: acc.bytes + dir_bytes(path)}

      {:ok, %File.Stat{type: :regular, size: size}} ->
        %{acc | bytes: acc.bytes + size}

      _other ->
        acc
    end
  end

  defp regular_size(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} -> size
      _other -> 0
    end
  end

  @doc """
  The bytes of the regular files directly in template `name` under `root`
  (links not followed); `0` for a missing one.
  """
  @spec template_bytes(Path.t(), String.t()) :: non_neg_integer()
  def template_bytes(root, name) when is_binary(root) and is_binary(name),
    do: dir_bytes(Path.join(root, name))

  defp dir_bytes(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.reduce(entries, 0, &(&2 + regular_size(Path.join(dir, &1))))

      {:error, _reason} ->
        0
    end
  end

  @doc """
  `path` with every symbolic link in it resolved, absolute — the directory
  or file it really is. `{:error, :enoent}` when a part of it does not
  exist, `{:error, :eloop}` after #{@max_links} links.
  """
  @spec realpath(Path.t()) :: {:ok, Path.t()} | {:error, atom()}
  def realpath(path) when is_binary(path) do
    ["/" | parts] = path |> Path.expand() |> Path.split()
    resolve(parts, "/", 0)
  end

  defp resolve([], resolved, _links), do: {:ok, resolved}
  defp resolve(_parts, _resolved, links) when links > @max_links, do: {:error, :eloop}

  defp resolve([part | rest], resolved, links) do
    candidate = Path.join(resolved, part)

    case :file.read_link_all(candidate) do
      {:ok, target} ->
        ["/" | target_parts] =
          target |> IO.chardata_to_string() |> Path.expand(resolved) |> Path.split()

        resolve(target_parts ++ rest, "/", links + 1)

      {:error, :einval} ->
        if File.exists?(candidate),
          do: resolve(rest, candidate, links),
          else: {:error, :enoent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The host's own files in template `name`: the regular files
  `Overrides.copy_template/3` would copy (not hidden, not leading out of the
  root) that are not template parts — `Overrides.list/1` does not show them
  (a marker such as `audience.txt`). Sorted; `[]` for a missing template or
  an invalid name.
  """
  @spec host_files(Path.t(), String.t()) :: [String.t()]
  def host_files(root, name) when is_binary(root) and is_binary(name) do
    dir = Path.join(root, name)

    with true <- Overrides.valid_name?(name),
         {:ok, entries} <- File.ls(dir) do
      parts =
        for %{name: ^name, files: files} <- Overrides.list(root),
            %{path: path} <- files,
            do: Path.basename(path)

      entries
      |> Enum.reject(&(String.starts_with?(&1, ".") or &1 in parts))
      |> Enum.filter(fn file ->
        match?({:ok, _}, Path.safe_relative(Path.join(name, file), root)) and
          File.regular?(Path.join(dir, file))
      end)
      |> Enum.sort()
    else
      _none -> []
    end
  end

  @doc "Whether `a` and `b` are the same existing directory or file, links resolved."
  @spec same_dir?(Path.t(), Path.t()) :: boolean()
  def same_dir?(a, b) when is_binary(a) and is_binary(b) do
    with {:ok, real_a} <- realpath(a),
         {:ok, real_b} <- realpath(b) do
      real_a == real_b
    else
      _error -> false
    end
  end

  @doc """
  `path` as a message may name it: relative to `root` when under it, else
  only its base name — never an absolute path.
  """
  @spec relative(Path.t(), Path.t()) :: String.t()
  def relative(root, path) do
    root = Path.expand(root)
    path = Path.expand(path)

    if String.starts_with?(path, root <> "/"),
      do: Path.relative_to(path, root),
      else: Path.basename(path)
  end
end
