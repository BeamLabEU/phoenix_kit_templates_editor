defmodule PhoenixKitTemplatesEditor.Watcher do
  @moduledoc """
  Where the template files are edited (`editable: true`) or watched
  (`watch: true`), a change made to them outside the editor — a hand edit,
  a `git pull` — reaches the next email without a restart: every 2 s this
  compares the files of the root — its own and each template directory's,
  by name, mtime and size — with its last look and, on a difference, drops
  the cached lookups (`PhoenixKitTemplatesEditor.Files.reload/1`, under
  every path string the directory is read by) and broadcasts
  `{:templates_editor, :files_changed}` on `topic/0` through PhoenixKit's
  PubSub.

  The module always lists it in `children/0`; it decides in `init/1`
  (`PhoenixKitTemplatesEditor.Config.watch_root/1`) and returns `:ignore`
  where it has nothing to do — production, whose files change only with a
  deploy, which restarts.

  A file rewritten within the same second at the same size is not seen —
  the editor drops the cache itself after its own writes. Links are looked
  at, not followed.
  """
  use GenServer

  require Logger

  alias PhoenixKit.PubSub.Manager, as: PubSub
  alias PhoenixKitTemplatesEditor.Config
  alias PhoenixKitTemplatesEditor.Files

  @interval 2_000
  @topic "phoenix_kit_templates_editor:files"

  @typedoc "The root's files: `{path under the root, mtime, size}`, sorted."
  @type snapshot :: [{String.t(), integer(), non_neg_integer()}]

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The PubSub topic a change of the files is broadcast on."
  @spec topic() :: String.t()
  def topic, do: @topic

  @impl true
  def init(opts) do
    case Config.watch_root() do
      {:ok, root} ->
        interval = Keyword.get(opts, :interval, @interval)
        schedule(interval)
        {:ok, %{root: root, interval: interval, snapshot: snapshot(root)}}

      :off ->
        :ignore
    end
  end

  @impl true
  def handle_info(:check, %{root: root, interval: interval, snapshot: previous} = state) do
    schedule(interval)
    {:noreply, %{state | snapshot: check(root, previous)}}
  end

  @doc """
  Compares the files of `root` now with `previous` (`snapshot/1`); when they
  differ, drops the cached lookups and broadcasts the change. The look now.
  """
  @spec check(Path.t(), snapshot()) :: snapshot()
  def check(root, previous) do
    case snapshot(root) do
      ^previous ->
        previous

      current ->
        Files.reload(root)
        broadcast()
        current
    end
  end

  @doc """
  The files of `root` — in it and in each directory in it — as
  `{path under the root, mtime, size}`, sorted; `[]` with no root. Links
  are taken as links, not followed.
  """
  @spec snapshot(Path.t()) :: snapshot()
  def snapshot(root) do
    root
    |> entries("")
    |> Enum.flat_map(fn
      {name, %File.Stat{type: :directory}} -> root |> entries(name) |> Enum.map(&file/1)
      entry -> [file(entry)]
    end)
    |> Enum.sort()
  end

  defp entries(root, dir) do
    case File.ls(Path.join(root, dir)) do
      {:ok, names} -> Enum.flat_map(names, &entry(root, relative(dir, &1)))
      {:error, _reason} -> []
    end
  end

  defp relative("", name), do: name
  defp relative(dir, name), do: Path.join(dir, name)

  defp entry(root, relative) do
    case File.lstat(Path.join(root, relative), time: :posix) do
      {:ok, stat} -> [{relative, stat}]
      {:error, _reason} -> []
    end
  end

  defp file({relative, %File.Stat{mtime: mtime, size: size}}), do: {relative, mtime, size}

  # Nobody listening, or PubSub not started (a bare test, a mix task): the
  # cache is dropped all the same.
  defp broadcast do
    PubSub.broadcast(@topic, {:templates_editor, :files_changed})
  rescue
    error ->
      Logger.debug("[PhoenixKitTemplatesEditor.Watcher] not broadcast: #{inspect(error)}")
      :ok
  end

  defp schedule(interval), do: Process.send_after(self(), :check, interval)
end
