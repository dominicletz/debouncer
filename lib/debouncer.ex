defmodule Debouncer do
  use Application
  use GenServer

  @moduledoc """
    Debouncer executes a function call debounced. Debouncing is done one a per key basis:

    ```
      Debouncer.apply(Key, fn() -> IO.puts("Hello World, debounced") end)
    ```

    The third optional parameter is the timeout period in milliseconds

    ```
      Debouncer.apply(Key, fn() -> IO.puts("Hello World, once per minute max") end, 60_000)
    ```

    The variants supported are:

    * apply()      => Events are executed after the timeout
    * immediate()  => Events are executed immediately, and further events are delayed for the timeout
    * immediate2() => Events are executed immediately, and further events are IGNORED for the timeout
    * delay()      => Each event delays the execution of the next event

    ```
    EVENT        X1---X2------X3-------X4----------
    TIMEOUT      ----------|----------|----------|-
    ===============================================
    apply()      ----------X2---------X3---------X4
    immediate()  X1--------X2---------X3---------X4
    immediate2() X1-----------X3-------------------
    delay()      --------------------------------X4
    ```


  """

  @spec immediate(term(), (() -> any()), non_neg_integer()) :: :ok
  @doc """
    immediate() executes the function immediately but blocks any further call
      under the same key for the given timeout.
  """
  def immediate(key, fun, timeout \\ 5000) do
    do_cast(fn state ->
      case Map.get(state, key) do
        nil ->
          execute(fun)
          calltime = time() + timeout
          ets_insert(calltime, key)
          Map.put(state, key, {calltime, nil, timeout})

        {calltime, _fun, _timeout} ->
          Map.put(state, key, {calltime, fun, timeout})
      end
    end)
  end

  @spec immediate2(term(), (() -> any()), non_neg_integer()) :: :ok
  @doc """
    immediate2() executes the function immediately but blocks any further call
      under the same key for the given timeout.
  """
  def immediate2(key, fun, timeout \\ 5000) do
    do_cast(fn state ->
      case Map.get(state, key) do
        nil ->
          execute(fun)
          calltime = time() + timeout
          ets_insert(calltime, key)
          Map.put(state, key, {calltime, nil, timeout})

        {calltime, _fun, _timeout} ->
          Map.put(state, key, {calltime, nil, timeout})
      end
    end)
  end

  @spec delay(term(), (() -> any()), non_neg_integer()) :: :ok
  @doc """
    delay() executes the function after the specified timeout t0 + timeout,
      when delay is called multipe times the timeout is reset based on the
      most recent call (t1 + timeout, t2 + timeout) etc... the fun is also updated
  """
  def delay(key, fun, timeout \\ 5000) do
    do_cast(fn state ->
      calltime = time() + timeout
      ets_insert(calltime, key)
      Map.put(state, key, {calltime, fun})
    end)
  end

  @spec apply(term(), (() -> any()), non_neg_integer()) :: :ok
  @doc """
    apply() executes the function after the specified timeout t0 + timeout,
      when apply is called multiple times it does not affect the point
      in time when the next call is happening (t0 + timeout) but updates the fun
  """
  def apply(key, fun, timeout \\ 5000) do
    do_cast(fn state ->
      case Map.get(state, key) do
        nil ->
          calltime = time() + timeout
          ets_insert(calltime, key)
          Map.put(state, key, {calltime, fun, timeout})

        {calltime, _fun, timeout} ->
          Map.put(state, key, {calltime, fun, timeout})
      end
    end)
  end

  @spec cancel(term()) :: :ok
  @doc """
    cancel() deletes the latest event if it hasn't triggered yet.
  """
  def cancel(key) do
    do_cast(fn state ->
      case Map.get(state, key) do
        nil ->
          state

        {calltime, _fun} ->
          Map.put(state, key, {calltime, nil})

        {calltime, _fun, timeout} ->
          Map.put(state, key, {calltime, nil, timeout})
      end
    end)
  end

  ######################## CALLBACKS       ####################
  @doc false
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    child = %{
      id: Debouncer,
      start: {Debouncer, :start_link, []}
    }

    Supervisor.start_link([child], strategy: :one_for_one, name: Debouncer.Supervisor)
  end

  @doc false
  @spec start_link() :: :ignore | {:error, any} | {:ok, pid}
  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  def init(_arg) do
    {:ok, _} = :timer.send_interval(100, :tick)
    __MODULE__ = :ets.new(__MODULE__, [{:keypos, 1}, :ordered_set, :named_table])
    {:ok, %{}}
  end

  ######################## INTERNAL METHOD ####################
  defp do_cast(fun) do
    GenServer.cast(__MODULE__, fun)
  end

  def handle_cast(fun, state) do
    {:noreply, fun.(state)}
  end

  defp ets_insert(calltime, key) do
    case :ets.lookup(__MODULE__, calltime) do
      [] -> :ets.insert(__MODULE__, {calltime, [key]})
      [{_, keys}] -> :ets.insert(__MODULE__, {calltime, [key | keys]})
    end
  end

  def handle_info(:tick, state) do
    {:noreply, update(state, time())}
  end

  defp update(state, now) do
    case :ets.first(__MODULE__) do
      :"$end_of_table" ->
        state

      ts when ts > now ->
        state

      ts ->
        state =
          hd(:ets.take(__MODULE__, ts))
          |> elem(1)
          |> Enum.reduce(state, fn key, state ->
            case Map.get(state, key) do
              # Handling apply(), immediate(), immediate2()
              {^ts, nil, _timeout} ->
                Map.delete(state, key)

              # Executing and putting marker for next event
              {^ts, fun, timeout} ->
                execute(fun)
                calltime = ts + timeout
                ets_insert(calltime, key)
                Map.put(state, key, {calltime, nil, timeout})

              # delay() goes here
              {^ts, fun} ->
                execute(fun)
                Map.delete(state, key)

              _ ->
                state
            end
          end)

        update(state, now)
    end
  end

  defp execute(nil) do
    :ok
  end

  defp execute(fun) do
    spawn(fun)
  end

  defp time() do
    System.monotonic_time(:millisecond)
  end
end
