# `Jido.Integration.V2.ControlPlane.EventStore`

Durable append-only event-ledger behaviour owned by `control_plane`.

# `append_events`

```elixir
@callback append_events(
  [Jido.Integration.V2.Event.t()],
  keyword()
) :: :ok | {:error, term()}
```

# `list_events`

```elixir
@callback list_events(String.t()) :: [Jido.Integration.V2.Event.t()]
```

# `next_seq`

```elixir
@callback next_seq(String.t(), String.t() | nil) :: non_neg_integer()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
