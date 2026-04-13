# `Jido.Integration.V2.WebhookRouter.Telemetry`

Package-owned `:telemetry` surface for hosted webhook route resolution.

Event families:

- `[:jido, :integration, :webhook_router, :route, :resolved]`
- `[:jido, :integration, :webhook_router, :route, :failed]`

Metadata is redacted through `Jido.Integration.V2.Redaction` and remains
supplemental to durable ingress and control-plane truth.

# `event_name`

```elixir
@type event_name() :: :route_resolved | :route_failed
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
