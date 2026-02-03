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

  * `apply/3`      => Events are executed after the timeout
  * `immediate/3`  => Events are executed immediately, and further events are delayed for the timeout
  * `immediate2/3` => Events are executed immediately, and further events are IGNORED for the timeout
  * `delay/3`      => Each event delays the execution of the next event

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

  defstruct events: %{}, workers: %{}, worker_monitors: %{}

  @doc """
  Executes the function immediately but blocks any further call
  under the same key for the given timeout.
  """
  def immediate(key, fun \\ nil, timeout \\ 5000) when is_integer(timeout) do
    {fun, timeout} = ensure_function(key, fun, timeout)

    do_cast(fn deb = %Debouncer{events: events} ->
      case Map.get(events, key) do
        nil ->
          new_event(deb, key, nil, timeout, timeout)
          |> execute(key, fun)

        {calltime, _fun, _timeout} ->
          events = Map.put(events, key, {calltime, fun, timeout})
          %Debouncer{deb | events: events}
      end
    end)
  end

  @doc """
  Executes the function immediately but ignores further calls
  under the same key for the given timeout.
  """
  def immediate2(key, fun \\ nil, timeout \\ 5000) when is_integer(timeout) do
    {fun, timeout} = ensure_function(key, fun, timeout)

    do_cast(fn deb = %Debouncer{events: events} ->
      case Map.get(events, key) do
        nil ->
          new_event(deb, key, nil, timeout, timeout)
          |> execute(key, fun)

        {calltime, _fun, _timeout} ->
          events = Map.put(events, key, {calltime, nil, timeout})
          %Debouncer{deb | events: events}
      end
    end)
  end

  @doc """
  Executes the function after the specified timeout t0 + timeout,
  when delay is called multipe times the timeout is reset based on the
  most recent call (t1 + timeout, t2 + timeout) etc... the fun is also updated
  """
  def delay(key, fun \\ nil, timeout \\ 5000) when is_integer(timeout) do
    {fun, timeout} = ensure_function(key, fun, timeout)

    do_cast(fn deb ->
      new_event(deb, key, fun, timeout, nil)
    end)
  end

  @doc """
  Executes the function after the specified timeout t0 + timeout,
  when apply is called multiple times it does not affect the point
  in time when the next call is happening (t0 + timeout) but updates the fun
  """
  def apply(key, fun \\ nil, timeout \\ 5000) when is_integer(timeout) do
    {fun, timeout} = ensure_function(key, fun, timeout)

    do_cast(fn deb = %Debouncer{events: events} ->
      case Map.get(events, key) do
        nil ->
          new_event(deb, key, fun, timeout, timeout)

        {calltime, _fun, timeout} ->
          events = Map.put(events, key, {calltime, fun, timeout})
          %Debouncer{deb | events: events}
      end
    end)
  end

  defp new_event(deb = %Debouncer{events: events}, key, fun, timeout, stall) do
    calltime = time() + timeout
    ets_insert(calltime, key)
    events = Map.put(events, key, {calltime, fun, stall})
    %Debouncer{deb | events: events}
  end

  @doc """
  Deletes the latest event if it hasn't triggered yet.
  """
  def cancel(key) do
    do_cast(fn deb = %Debouncer{events: events} ->
      case Map.get(events, key) do
        nil ->
          deb

        {calltime, _fun, timeout} ->
          events = Map.put(events, key, {calltime, nil, timeout})
          %Debouncer{deb | events: events}
      end
    end)
  end

  @doc """
  Returns the pid of an active job worker or nil if no such job is scheduled.
  Per key the debouncer never starts more than one process at the same time.
  """
  def worker(key) do
    GenServer.call(__MODULE__, {:worker, key})
  end

  @doc """
  Returns a map of all active job workers. This is useful for debugging of
  active workers and profiling.
  """
  def workers do
    GenServer.call(__MODULE__, :workers)
    |> Enum.map(fn {key, {pid, _fun, _repeat?}} -> {key, pid} end)
    |> Enum.into(%{})
  end

  @doc """
  Returns a map of all events. This is useful for debugging of active events and
  profiling.
  """
  def events do
    # only select the first element of the tuple
    :ets.tab2list(__MODULE__) |> Enum.map(fn {_ts, keys} -> keys end) |> List.flatten()
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
  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  def init(_arg) do
    {:ok, _} = :timer.send_interval(100, :tick)
    __MODULE__ = :ets.new(__MODULE__, [{:keypos, 1}, :ordered_set, :named_table])
    {:ok, %Debouncer{}}
  end

  ######################## INTERNAL METHOD ####################
  defp do_cast(fun) do
    GenServer.cast(__MODULE__, fun)
  end

  def handle_cast(fun, state) do
    {:noreply, fun.(state)}
  end

  def handle_call(:workers, _from, state = %Debouncer{workers: workers}) do
    {:reply, workers, state}
  end

  def handle_call({:worker, key}, _from, state = %Debouncer{workers: workers}) do
    case Map.get(workers, key) do
      nil ->
        {:reply, nil, state}

      {pid, _fun, _repeat?} ->
        {:reply, pid, state}
    end
  end

  defp ets_insert(calltime, key) do
    case :ets.lookup(__MODULE__, calltime) do
      [] -> :ets.insert(__MODULE__, {calltime, [key]})
      [{_, keys}] -> :ets.insert(__MODULE__, {calltime, [key | keys]})
    end
  end

  def handle_info(:tick, deb) do
    {:noreply, update(deb, time())}
  end

  def handle_info(
        {:DOWN, ref, :process, end_pid, _reason},
        deb = %Debouncer{workers: workers, worker_monitors: worker_monitors}
      ) do
    key = Map.get(worker_monitors, ref)
    {^end_pid, fun, repeat?} = Map.get(workers, key)
    workers = Map.delete(workers, key)
    worker_monitors = Map.delete(worker_monitors, ref)

    if map_size(workers) == 0 do
      :erlang.garbage_collect()
    end

    deb = %Debouncer{deb | workers: workers, worker_monitors: worker_monitors}

    if repeat? do
      {:noreply, execute(deb, key, fun)}
    else
      {:noreply, deb}
    end
  end

  defp update(deb, now) do
    case :ets.first(__MODULE__) do
      :"$end_of_table" ->
        deb

      ts when ts > now ->
        deb

      ts ->
        hd(:ets.take(__MODULE__, ts))
        |> elem(1)
        |> reduce_events(deb, ts)
        |> update(now)
    end
  end

  defp reduce_events(events, deb, ts) do
    Enum.reduce(events, deb, fn key, deb = %Debouncer{events: events} ->
      case Map.get(events, key) do
        # Handling apply(), immediate(), immediate2()
        {^ts, nil, _timeout} ->
          events = Map.delete(events, key)
          %Debouncer{deb | events: events}

        # Executing and putting marker for next event
        {^ts, fun, timeout} when is_integer(timeout) ->
          calltime = ts + timeout
          ets_insert(calltime, key)
          events = Map.put(events, key, {calltime, nil, timeout})

          %Debouncer{deb | events: events}
          |> execute(key, fun)

        # delay() goes here
        {^ts, fun, nil} ->
          events = Map.delete(events, key)

          %Debouncer{deb | events: events}
          |> execute(key, fun)

        _ ->
          deb
      end
    end)
  end

  defp execute(deb, _key, nil) do
    deb
  end

  defp execute(deb = %Debouncer{workers: workers, worker_monitors: worker_monitors}, key, fun) do
    case Map.get(workers, key) do
      nil ->
        pid = spawn_worker(fun)
        ref = Process.monitor(pid)
        worker_monitors = Map.put(worker_monitors, ref, key)
        worker = {pid, fun, false}
        %Debouncer{deb | workers: Map.put(workers, key, worker), worker_monitors: worker_monitors}

      {pid, _fun, _repeat?} ->
        # Execute this after the current job finishes
        worker = {pid, fun, true}
        %Debouncer{deb | workers: Map.put(workers, key, worker), worker_monitors: worker_monitors}
    end
  end

  defp spawn_worker(fun) when is_function(fun, 0) do
    spawn(__MODULE__, :work, [fun])
  end

  defp spawn_worker({m, f, a}) when is_atom(m) and is_atom(f) and is_list(a) do
    spawn(m, f, a)
  end

  @doc false
  def work(fun) do
    fun.()
  end

  defp time do
    System.monotonic_time(:millisecond)
  end

  defp ensure_function(_key, fun, timeout) when is_function(fun, 0) and is_integer(timeout) do
    {fun, timeout}
  end

  defp ensure_function(_key, {m, f, a}, timeout)
       when is_atom(m) and is_atom(f) and is_list(a) and is_integer(timeout) do
    {{m, f, a}, timeout}
  end

  defp ensure_function(key, nil, timeout) when is_function(key, 0) and is_integer(timeout) do
    check_function(key)
    {key, timeout}
  end

  defp ensure_function(key, timeout, _timeout) when is_function(key, 0) and is_integer(timeout) do
    check_function(key)
    {key, timeout}
  end

  defp ensure_function({m, f, a}, nil, timeout)
       when is_atom(m) and is_atom(f) and is_list(a) and is_integer(timeout) do
    {{m, f, a}, timeout}
  end

  defp ensure_function({m, f, a}, timeout, _timeout)
       when is_atom(m) and is_atom(f) and is_list(a) and is_integer(timeout) do
    {{m, f, a}, timeout}
  end

  defp check_function(key) do
    info = :erlang.fun_info(key)

    if info[:type] == :local and String.contains?("#{info[:name]}", "-fun-") do
      raise "In-place function definitions can not be used in the shorthand, as those create a different key on every call. So the debounce counting won't work."
    end
  end
end
