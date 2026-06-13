Mix.Task.run("app.start")

defmodule Debouncer.Bench do
  @trials 100
  @timeout_ms 100
  @idle_ms 2_000

  def run do
    IO.puts("# Debouncer timer benchmark\n")
    IO.puts("Implementation: #{implementation()}\n")

    idle = measure_idle()
    latency = measure_latency()
    smoke = functional_smoke()

    print_table(idle, latency, smoke)
  end

  defp implementation do
    if Process.whereis(Debouncer.Timer), do: "event-driven (Debouncer.Timer)", else: "polling (:tick)"
  end

  defp measure_idle do
    debouncer = Process.whereis(Debouncer)
    timer_pid = Process.whereis(Debouncer.Timer)

    {_, r0} = :erlang.process_info(debouncer, :reductions)

    t0 =
      if timer_pid do
        {_, tr0} = :erlang.process_info(timer_pid, :reductions)
        tr0
      end

    Process.sleep(@idle_ms)

    {_, r1} = :erlang.process_info(debouncer, :reductions)

    timer =
      if timer_pid do
        {_, tr1} = :erlang.process_info(timer_pid, :reductions)
        tr1 - t0
      end

    %{debouncer: r1 - r0, timer: timer}
  end

  defp measure_latency do
    parent = self()

    slacks =
      for i <- 1..@trials do
        key = {:bench, i}
        scheduled_at = System.monotonic_time(:millisecond)

        Debouncer.apply(key, fn ->
          fired_at = System.monotonic_time(:millisecond)
          send(parent, {:fired, key, fired_at})
        end, @timeout_ms)

        receive do
          {:fired, ^key, fired_at} -> fired_at - (scheduled_at + @timeout_ms)
        after
          @timeout_ms + 500 -> raise "timeout waiting for fire on trial #{i}"
        end
      end

    sorted = Enum.sort(slacks)
    p50 = percentile(sorted, 0.50)
    p95 = percentile(sorted, 0.95)

    %{
      min: Enum.min(slacks),
      max: Enum.max(slacks),
      avg: Enum.sum(slacks) / length(slacks),
      p50: p50,
      p95: p95
    }
  end

  defp percentile(sorted, p) do
    idx = max(0, round(p * (length(sorted) - 1)))
    Enum.at(sorted, idx)
  end

  defp functional_smoke do
    table = :debouncer_bench_smoke

    if :ets.whereis(table) == :undefined do
      :ets.new(table, [:named_table, :public, :set])
    else
      :ets.delete_all_objects(table)
    end

    key = :smoke

    Debouncer.apply(key, fn -> :ets.update_counter(table, :count, 1, {:count, 0}) end, 200)
    Process.sleep(500)
    Debouncer.apply(key, fn -> :ets.update_counter(table, :count, 2, {:count, 0}) end, 200)
    Process.sleep(800)

    case :ets.lookup(table, :count) do
      [{:count, n}] -> n
      [] -> 0
    end
  end

  defp print_table(idle, latency, smoke) do
    timer_row =
      case idle.timer do
        nil -> "| Idle Timer reductions     | n/a (polling) |"
        n -> "| Idle Timer reductions     | #{n} |"
      end

    IO.puts("""
    | Metric                    | Value |
    |---------------------------|-------|
    | Idle Debouncer reductions | #{idle.debouncer} |
    #{timer_row}
    | Latency min slack (ms)    | #{latency.min} |
    | Latency avg slack (ms)    | #{Float.round(latency.avg, 1)} |
    | Latency p50 slack (ms)    | #{latency.p50} |
    | Latency p95 slack (ms)    | #{latency.p95} |
    | Latency max slack (ms)    | #{latency.max} |
    | Smoke test counter        | #{smoke} |
    """)
  end
end

Debouncer.Bench.run()
