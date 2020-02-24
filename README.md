# Debouncer

Debouncer library to reduce frequency of function calls to alerts, updates and similar. It supports four different modes:

* apply      - For delayed triggers, e.g. to trigger an __autocomplete__ action
* immediate  - For reducing frequency of events, the first event per intervall is delivered immediately, e.g. trigger __data processing tasks__ 
* immediate2 - Similiar to immediate but never delays events, either forwards them or ignores them, e.g. to trigger __alert emails__ 
* delay      - Only triggers an event after the timeout period, any further event delays the trigger. E.g. to detect data streams that __ended actvitiy__ 

## Example

```
  Debouncer.apply(SomeKey, fn() -> 
    IO.puts("Hello World, debounced will appear in 5 seconds") 
  end)
```

```
  Debouncer.immediate(OtherKey, fn() -> 
    IO.puts("Hello World, will appear immediate, but not again within 5 seconds") 
  end)
```
## Installation

The debouncer can be installed by adding `debouncer` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:debouncer, "~> 0.1.0"}
  ]
end
```

The debouncer is an application and will start a GenServer to trigger the events. To include the Application in your release add it to your extra applications:

```elixir
  def application do
    [
      mod: {Your.Application, []},
      extra_applications: [:debouncer]
    ]
  end

```

If it's not started it will try to start itself on usage.

The docs can be found at [https://hexdocs.pm/debouncer](https://hexdocs.pm/debouncer).