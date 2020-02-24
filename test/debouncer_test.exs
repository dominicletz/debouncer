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

  defp incr(value) do
    :ets.update_counter(:debounce_test, :first, value, {:first, 0})
  end

  defp get() do
    [{:first, num}] = :ets.lookup(:debounce_test, :first)
    num
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
end
