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

  @file_mode 0o664
  @dir_mode 0o2775
  @max_links 40
  @git_timeout 5_000

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
  What the editor calls after it wrote `paths` under `root` (a new template
  directory first, then files): each file is made `0664` and each directory
  `2775` — group-writable, a directory passing its group on — so the people
  of the tree's group can go on working with them through git; then
  `reload/1`.

  Ownership is never changed: the root is meant to be a setgid directory of
  the tree owner's group (README, installation). A symbolic link is left
  alone, never followed. The files are saved by then: a path whose mode
  cannot be set is logged and returned as `{:warning, message}`, never an
  error, and the cache is dropped all the same.
  """
  @spec after_write(Path.t(), [Path.t()]) :: :ok | {:warning, String.t()}
  def after_write(root, paths) when is_binary(root) and is_list(paths) do
    problems = Enum.flat_map(paths, &settle_mode(root, &1))

    case problems do
      [] ->
        :ok

      problems ->
        message = Enum.join(problems, "; ")
        Logger.warning("[PhoenixKitTemplatesEditor] saved, but #{message}")
        {:warning, message}
    end
  after
    reload(root)
  end

  defp settle_mode(root, path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} -> chmod(root, path, @file_mode)
      {:ok, %File.Stat{type: :directory}} -> chmod(root, path, @dir_mode)
      {:ok, %File.Stat{}} -> ["#{relative(root, path)}: not a plain file, mode left as it is"]
      {:error, reason} -> ["#{relative(root, path)}: mode not set (#{format_error(reason)})"]
    end
  end

  defp chmod(root, path, mode) do
    case File.chmod(path, mode) do
      :ok -> []
      {:error, reason} -> ["#{relative(root, path)}: mode not set (#{format_error(reason)})"]
    end
  end

  @doc """
  The files under `root` that differ from git's last commit — changed, new
  or deleted — by their paths in the repository, sorted: a change made in
  the editor reaches another server only once it is committed.

  Asked as `git -c core.fsmonitor=false --no-optional-locks status
  --porcelain=v1 -z --untracked-files=all --no-renames -- .` in `root`:
  no hook the repository configures runs, git never rewrites the index (the
  server may run as another user than the tree's owner), and no `GIT_*`
  variable of the server's environment points it elsewhere. `[]` when the
  root is not in a git work tree, git is not installed, or it does not
  answer within #{div(@git_timeout, 1000)} s.
  """
  @spec uncommitted(Path.t()) :: [String.t()]
  def uncommitted(root) when is_binary(root) do
    with true <- File.dir?(root),
         git when is_binary(git) <- System.find_executable("git"),
         {:ok, {output, 0}} <- Bounded.run(fn -> git_status(git, root) end, @git_timeout) do
      output |> String.split(<<0>>, trim: true) |> Enum.flat_map(&status_path/1) |> Enum.sort()
    else
      {:error, :timeout} ->
        Logger.warning("[PhoenixKitTemplatesEditor] git status did not answer in time")
        []

      _no_status ->
        []
    end
  end

  defp git_status(git, root) do
    args =
      ~w(-c core.fsmonitor=false --no-optional-locks status --porcelain=v1 -z) ++
        ~w(--untracked-files=all --no-renames -- .)

    System.cmd(git, args, cd: root, env: clean_git_env(), stderr_to_stdout: false)
  end

  defp clean_git_env do
    for {name, _value} <- System.get_env(), String.starts_with?(name, "GIT_"), do: {name, nil}
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

  defp format_error(reason), do: reason |> :file.format_error() |> to_string()
end
