defmodule PhoenixKitTemplatesEditor.Throttle do
  @moduledoc """
  "Not more often than once in so long" per key — for "Send to me" (one
  test email per user every 30 s). One public ETS table,
  owned by this process (a child of the module, `children/0`), so a key's
  last time outlives the page that set it.
  """

  use GenServer

  @table __MODULE__

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  @doc """
  `:ok` and the key's time set to now, when it was last set more than
  `interval_ms` ago or never; else `{:error, {:wait, seconds}}` — how long
  until it may. `{:error, :unavailable}` without the table (the process
  not started): refused, not let through.
  """
  @spec hit(term(), pos_integer()) :: :ok | {:error, {:wait, pos_integer()} | :unavailable}
  def hit(key, interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    now = System.monotonic_time(:millisecond)

    cond do
      :ets.whereis(@table) == :undefined ->
        {:error, :unavailable}

      :ets.insert_new(@table, {key, now}) ->
        :ok

      # Atomic: only one of two clicks at the same moment takes the slot.
      :ets.select_replace(@table, [
        {{key, :"$1"}, [{:"=<", :"$1", now - interval_ms}], [{{{:const, key}, now}}]}
      ]) == 1 ->
        :ok

      true ->
        wait(key, now, interval_ms)
    end
  rescue
    ArgumentError -> {:error, :unavailable}
  end

  defp wait(key, now, interval_ms) do
    case :ets.lookup(@table, key) do
      [{^key, last}] -> {:error, {:wait, max(div(last + interval_ms - now + 999, 1000), 1)}}
      [] -> {:error, {:wait, 1}}
    end
  end
end
