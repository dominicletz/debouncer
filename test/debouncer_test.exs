defmodule DebouncerTest do
  use ExUnit.Case
  @timeout 500
  @pause 500

  setup_all do
    :debounce_test = :ets.new(:debounce_test, [:named_table, :public])
    :ok
  end

  defp reset() do
    :ets.insert(:debounce_test, {:first, 0})
    make_ref()
  end

  def incr(value) do
    :ets.update_counter(:debounce_test, :first, value, {:first, 0})
  end

  def incr_133() do
    incr(133)
  end

  defp get() do
    [{:first, num}] = :ets.lookup(:debounce_test, :first)
    num
  end

  def readme(fun) do
    run(fn key ->
      fun.(key, fn -> incr(1) end, 1000)
      Process.sleep(500)
      fun.(key, fn -> incr(2) end, 1000)
      Process.sleep(800)
      fun.(key, fn -> incr(3) end, 1000)
      Process.sleep(900)
      fun.(key, fn -> incr(4) end, 1000)
      Process.sleep(1200)
    end)
  end

  def run(fun) do
    fun.(reset())
    get()
  end

  test "example from the readme" do
    assert readme(&Debouncer.apply/3) == 2 + 3 + 4
    assert readme(&Debouncer.immediate/3) == 1 + 2 + 3 + 4
    assert readme(&Debouncer.immediate2/3) == 1 + 3
    assert readme(&Debouncer.delay/3) == 4
  end

  test "mfa" do
    assert run(fn _key ->
             Debouncer.immediate(:some_job, {__MODULE__, :incr, [133]}, 1000)
             Process.sleep(100)
           end) == 133

    assert run(fn _key ->
             Debouncer.immediate({__MODULE__, :incr, [133]}, 1000)
             Process.sleep(100)
           end) == 133

    assert fn -> incr(133) end != fn -> incr(133) end
    assert (&incr_133/0) == (&incr_133/0)

    assert run(fn _key ->
             Debouncer.immediate(&incr_133/0, 1000)
             Process.sleep(100)
           end) == 133

    assert run(fn _key ->
             Debouncer.immediate(fn -> incr(133) end)
             Process.sleep(100)
           end) == 133
  end

  def cancel(fun) do
    key = reset()
    fun.(key, fn -> incr(1) end, 1000)
    Process.sleep(500)
    fun.(key, fn -> incr(2) end, 1000)
    Process.sleep(800)
    fun.(key, fn -> incr(3) end, 1000)
    Process.sleep(900)
    fun.(key, fn -> incr(4) end, 1000)
    Debouncer.cancel(key)
    Process.sleep(1200)
    get()
  end

  test "example from the readme + delete" do
    assert cancel(&Debouncer.apply/3) == 2 + 3
    assert cancel(&Debouncer.immediate/3) == 1 + 2 + 3
    assert cancel(&Debouncer.immediate2/3) == 1 + 3
    assert cancel(&Debouncer.delay/3) == 0
  end

  def debounce(fun) do
    key = reset()
    fun.(key, fn -> incr(1) end, @timeout)
    fun.(key, fn -> incr(3) end, @timeout)
    fun.(key, fn -> incr(5) end, @timeout)
    fun.(key, fn -> incr(7) end, @timeout)
    fun.(key, fn -> incr(11) end, @timeout)
    Process.sleep(@timeout + @pause)
    get()
  end

  test "1,3,5,7,11 debounce()" do
    # Apply and Delay behave the same here as both fire only on the the last event
    assert debounce(&Debouncer.apply/3) == 11
    assert debounce(&Debouncer.delay/3) == 11

    # Immediate fires the first (1) AND the last (11) event
    assert debounce(&Debouncer.immediate/3) == 12
    # Immediate2 only fires the first event
    assert debounce(&Debouncer.immediate2/3) == 1
  end

  ## Simplest case: We fire 1 event and wait
  def once(fun) do
    key = reset()
    fun.(key, fn -> incr(1) end, @timeout)
    Process.sleep(@timeout + @pause)
    get()
  end

  test "1 once()" do
    # all behave the same here
    assert once(&Debouncer.apply/3) == 1
    assert once(&Debouncer.delay/3) == 1
    assert once(&Debouncer.immediate/3) == 1
    assert once(&Debouncer.immediate2/3) == 1
  end

  ## Simplest case: We fire 1 event and wait
  def overlapp(fun) do
    key = reset()

    fun.(
      key,
      fn ->
        incr(1)
        Process.sleep(4 * @timeout)
      end,
      @timeout
    )

    # This should not have an effect, because the previous call
    # did not finish yet
    Process.sleep(@timeout + @pause)
    fun.(key, fn -> incr(1) end, @timeout)
    Process.sleep(@pause)

    ret = get()
    Process.sleep(3 * @timeout)
    ret
  end

  test "1 overlapp()" do
    # all behave the same here
    assert overlapp(&Debouncer.apply/3) == 1
    assert overlapp(&Debouncer.delay/3) == 1
    assert overlapp(&Debouncer.immediate/3) == 1
    assert overlapp(&Debouncer.immediate2/3) == 1
  end

  # Ten events each with a small 100ms pause
  def ten_pauses(fun) do
    key = reset()

    for _ <- 1..10 do
      fun.(key, fn -> incr(3) end, @timeout)
      Process.sleep(100)
    end

    Process.sleep(@pause)
    get()
  end

  test "1..10 ten_pauses()" do
    # Apply trigger two times
    assert ten_pauses(&Debouncer.apply/3) == 6
    # Delay triggers only on the last one
    assert ten_pauses(&Debouncer.delay/3) == 3

    # Immediate triggers four times?
    assert ten_pauses(&Debouncer.immediate/3) == 9

    # Immediate2 triggers three times
    assert ten_pauses(&Debouncer.immediate2/3) == 6
  end

  test "worker" do
    here = self()

    Debouncer.immediate(:some_job, fn ->
      send(here, :start)

      receive do
        :run -> :ok
      end

      send(here, :finish)
    end)

    assert_receive :start
    send(Debouncer.worker(:some_job), :run)
    assert_receive :finish
  end
end
