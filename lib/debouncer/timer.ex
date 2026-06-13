defmodule Debouncer.Timer do
  @moduledoc false

  @deadlines Debouncer.Timer.Deadlines
  @keys Debouncer.Timer.Keys

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :worker
    }
  end

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts \\ []) do
    debouncer = Keyword.fetch!(opts, :debouncer)
    name = Keyword.get(opts, :name, __MODULE__)
    deadlines_table = Keyword.get(opts, :deadlines_table, @deadlines)
    keys_table = Keyword.get(opts, :keys_table, @keys)

    pid =
      spawn_link(fn ->
        init_tables(deadlines_table, keys_table)
        reconcile(debouncer)
        loop(debouncer, deadlines_table, keys_table)
      end)

    Process.register(pid, name)
    {:ok, pid}
  end

  def schedule(calltime, key) do
    send(__MODULE__, {:schedule, calltime, key})
  end

  def cancel(key) do
    send(__MODULE__, {:cancel, key})
  end

  def reschedule(key, old_ts, new_ts) do
    send(__MODULE__, {:reschedule, key, old_ts, new_ts})
  end

  def scheduled_keys(deadlines_table \\ @deadlines) do
    :ets.tab2list(deadlines_table)
    |> Enum.flat_map(fn {_ts, keys} -> keys end)
  end

  defp init_tables(deadlines_table, keys_table) do
    for {table, type} <- [{deadlines_table, :ordered_set}, {keys_table, :set}] do
      case :ets.whereis(table) do
        :undefined -> :ets.new(table, [type, :named_table, :protected])
        _ -> :ets.delete_all_objects(table)
      end
    end
  end

  defp loop(debouncer, deadlines_table, keys_table) do
    receive do
      {:schedule, calltime, key} ->
        schedule_key(deadlines_table, keys_table, calltime, key)

      {:reschedule, key, old_ts, new_ts} ->
        remove_key(deadlines_table, keys_table, old_ts, key)
        schedule_key(deadlines_table, keys_table, new_ts, key)

      {:cancel, key} ->
        cancel_key(deadlines_table, keys_table, key)
    after
      next_timeout_ms(deadlines_table) ->
        fire_due(debouncer, deadlines_table, keys_table)
    end

    loop(debouncer, deadlines_table, keys_table)
  end

  defp reconcile(debouncer) when is_atom(debouncer) do
    case GenServer.whereis(debouncer) do
      nil ->
        :ok

      _ ->
        debouncer
        |> GenServer.call(:pending_schedules)
        |> Enum.each(fn {key, calltime} ->
          schedule_key(@deadlines, @keys, calltime, key)
        end)
    end
  end

  defp reconcile(_debouncer), do: :ok

  defp schedule_key(deadlines_table, keys_table, calltime, key) do
    :ets.insert(keys_table, {key, calltime})
    insert_bucket(deadlines_table, calltime, key)
  end

  defp cancel_key(deadlines_table, keys_table, key) do
    case :ets.lookup(keys_table, key) do
      [{^key, calltime}] ->
        :ets.delete(keys_table, key)
        remove_bucket(deadlines_table, calltime, key)

      [] ->
        :ok
    end
  end

  defp remove_key(deadlines_table, keys_table, calltime, key) do
    :ets.delete(keys_table, key)
    remove_bucket(deadlines_table, calltime, key)
  end

  defp next_timeout_ms(deadlines_table) do
    case :ets.first(deadlines_table) do
      :"$end_of_table" -> :infinity
      ts -> max(0, ts - time())
    end
  end

  defp fire_due(debouncer, deadlines_table, keys_table) do
    fire_due(debouncer, deadlines_table, keys_table, time())
  end

  defp fire_due(debouncer, deadlines_table, keys_table, now) do
    case :ets.first(deadlines_table) do
      :"$end_of_table" ->
        :ok

      ts when ts > now ->
        :ok

      ts ->
        keys = take_bucket(deadlines_table, ts)
        Enum.each(keys, &:ets.delete(keys_table, &1))
        GenServer.cast(debouncer, {:due, ts, keys})
        fire_due(debouncer, deadlines_table, keys_table, now)
    end
  end

  defp insert_bucket(table, calltime, key) do
    case :ets.lookup(table, calltime) do
      [] ->
        :ets.insert(table, {calltime, [key]})

      [{^calltime, keys}] ->
        :ets.insert(table, {calltime, [key | keys]})
    end
  end

  defp remove_bucket(table, calltime, key) do
    case :ets.lookup(table, calltime) do
      [] ->
        :ok

      [{^calltime, keys}] ->
        keys = List.delete(keys, key)

        if keys == [] do
          :ets.delete(table, calltime)
        else
          :ets.insert(table, {calltime, keys})
        end
    end
  end

  defp take_bucket(table, calltime) do
    case :ets.take(table, calltime) do
      [{^calltime, keys}] -> keys
      _ -> []
    end
  end

  defp time do
    System.monotonic_time(:millisecond)
  end
end
