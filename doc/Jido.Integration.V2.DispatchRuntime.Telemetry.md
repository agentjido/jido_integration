# `Jido.Integration.V2.DispatchRuntime.Telemetry`

Package-owned `:telemetry` surface for async dispatch lifecycle observation.

Event families:

- `[:jido, :integration, :dispatch_runtime, :enqueue]`
- `[:jido, :integration, :dispatch_runtime, :deliver]`
- `[:jido, :integration, :dispatch_runtime, :retry]`
- `[:jido, :integration, :dispatch_runtime, :dead_letter]`
- `[:jido, :integration, :dispatch_runtime, :replay]`

Metadata is redacted through `Jido.Integration.V2.Redaction` and remains
supplemental to durable control-plane `Event` records.

# `event_name`

```elixir
@type event_name() :: :enqueue | :deliver | :retry | :dead_letter | :replay
```

# `emit`

```elixir
@spec emit(event_name(), map(), map()) :: :ok
```

# `event`

```elixir
@spec event(event_name()) :: [atom()]
```

# `events`

```elixir
@spec events() :: %{required(event_name()) =&gt; [atom()]}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
