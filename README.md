# Debouncer ![Build](https://github.com/dominicletz/debouncer/actions/workflows/test.yml/badge.svg)

Debouncer module to reduce frequency of function calls to alerts, updates and similar. It supports four different modes:

* `apply()`      - For delayed triggers, e.g. to trigger an __autocomplete__ action
* `immediate()`  - For reducing frequency of events, the first event per interval is delivered immediately, e.g. trigger __data processing tasks__ 
* `immediate2()` - Similiar to immediate but never delays events, either forwards them or ignores them, e.g. to trigger __alert emails__ 
* `delay()`      - Only triggers an event after the timeout period, any further event delays the trigger. E.g. to detect data streams that __ended actvitiy__ 

## Usage Example

```elixir
  Debouncer.apply(SomeKey, fn() -> 
    IO.puts("Hello World, debounced will appear in 5 seconds") 
  end)
```

```elixir
  Debouncer.immediate(OtherKey, fn() -> 
    IO.puts("Hello World, will appear immediate, but not again within 5 seconds") 
  end)
```

## Behaviour Graph

```
EVENT        E1---E2------E3-------E4----------
TIMEOUT      ----------|----------|----------|-
===============================================
apply()      ----------E2---------E3---------E4
immediate()  E1--------E2---------E3---------E4
immediate2() E1-----------E3-------------------
delay()      --------------------------------E4

USE CASE
apply()      - Search input field
immediate()  - Send email now, but not too freq
immediate2() - Game gun with reload time
delay()      - Schedule post-processing job
```

This graph represents when the different variants fire an event respectively on a timeline. In code the first line would look like this:

```elixir
fn ->
  Debouncer.apply(SomeKey, fn() -> IO.puts("X1") end, 1000)
  Process.sleep(500)
  Debouncer.apply(SomeKey, fn() -> IO.puts("X2") end, 1000)
  Process.sleep(800)
  Debouncer.apply(SomeKey, fn() -> IO.puts("X3") end, 1000)
  Process.sleep(900)
  Debouncer.apply(SomeKey, fn() -> IO.puts("X4") end, 1000)
  Process.sleep(1200)
end.()

> X2
> X3
> X4
```

## Shorthands

When using Module-Function-Argument tuples as callbacks (aka `mfa`) it can be convenient to skip the key and use the mfa itself as key:

```elixir
# Call later() function immediately with the default 5 second debounce:
Debouncer.immediate({__MODULE__, :later, []})

# Call later() function immediately with 1 second debounce:
Debouncer.immediate({__MODULE__, :later, []}, 1_000)

# Same but in using method binding
Debouncer.immediate(&later/0, 1_000)

# Same but in using method binding
Debouncer.immediate(&later/0, 1_000)
```

**NOTE**

Do not use in-place fun definitions can not be used in the shorthand, as those create a different key on every.

Example:

```elixir
# Because (`fn -> 1 end != fn -> 1 end`) don't do this:
Debouncer.immediate(fn -> later() end, 1_000)
```


## Installation

The debouncer can be installed by adding `debouncer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:debouncer, "~> 1.0"}
  ]
end
```

The docs can be found at [https://hexdocs.pm/debouncer](https://hexdocs.pm/debouncer).

## Remarks

Scheduling uses a dedicated timer process that sleeps with `receive after` until the next deadline (or until a new event is scheduled). There is no fixed polling interval, so idle systems incur no timer wakeups and short timeouts fire with millisecond precision.

Compare before/after locally:

```bash
mix bench | tee bench/after.txt
```

On the previous polling implementation, `mix bench` typically showed non-zero idle Debouncer reductions and higher p95/max fire slack at 100ms timeouts.

The `delay()` behaviour is the same as in Michal Muskalas Debounce implementation https://github.com/michalmuskala/debounce