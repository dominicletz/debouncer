defmodule Debouncer.TimerTest.Receiver do
  @moduledoc false
  use GenServer

  def start_link(test_pid) do
    GenServer.start_link(__MODULE__, test_pid, [])
  end

  @impl true
  def init(test_pid), do: {:ok, test_pid}

  @impl true
  def handle_cast({:due, ts, keys}, test_pid) do
    send(test_pid, {:due, ts, keys})
    {:noreply, test_pid}
  end

  @impl true
  def handle_call(:pending_schedules, _from, test_pid) do
    {:reply, [], test_pid}
  end
end

defmodule Debouncer.TimerTest do
  use ExUnit.Case

  alias Debouncer.Timer, as: DebouncerTimer
  alias Debouncer.TimerTest.Receiver

  setup do
    id = System.unique_integer([:positive])
    timer_name = :"Debouncer.Timer.Test.#{id}"
    deadlines_table = :"Debouncer.Timer.Deadlines.Test.#{id}"
    keys_table = :"Debouncer.Timer.Keys.Test.#{id}"

    {:ok, debouncer} = Receiver.start_link(self())

    {:ok, timer_pid} =
      DebouncerTimer.start_link(
        debouncer: debouncer,
        name: timer_name,
        deadlines_table: deadlines_table,
        keys_table: keys_table
      )

    on_exit(fn -> Process.exit(timer_pid, :normal) end)

    %{timer: timer_name}
  end

  test "idle does not fire due messages" do
    Process.sleep(500)
    refute_receive {:due, _, _}, 10
  end

  test "schedule fires at deadline", %{timer: timer} do
    key = :test_key
    calltime = System.monotonic_time(:millisecond) + 50
    send(timer, {:schedule, calltime, key})

    assert_receive {:due, ts, keys}, 200
    assert ts == calltime
    assert keys == [key]
  end

  test "reschedule fires at new deadline", %{timer: timer} do
    key = :reschedule_key
    now = System.monotonic_time(:millisecond)
    send(timer, {:schedule, now + 5000, key})
    Process.sleep(10)
    send(timer, {:reschedule, key, now + 5000, now + 50})

    assert_receive {:due, ts, keys}, 200
    assert ts == now + 50
    assert keys == [key]
    refute_receive {:due, _, _}, 100
  end

  test "cancel prevents due message", %{timer: timer} do
    key = :cancel_key
    send(timer, {:schedule, System.monotonic_time(:millisecond) + 100, key})
    Process.sleep(10)
    send(timer, {:cancel, key})
    refute_receive {:due, _, _}, 200
  end

  test "reconcile restores schedules after timer restart" do
    key = :reconcile_job
    Debouncer.apply(key, fn -> :ok end, 5000)
    :sys.get_state(Debouncer)
    assert key in Debouncer.events()

    timer_pid = Process.whereis(Debouncer.Timer)
    ref = Process.monitor(timer_pid)
    Process.exit(timer_pid, :kill)

    assert_receive {:DOWN, ^ref, :process, ^timer_pid, _}, 1000
    Process.sleep(100)

    assert Process.whereis(Debouncer.Timer)
    assert key in Debouncer.events()
  end
end
