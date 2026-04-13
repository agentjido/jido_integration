# `Jido.Integration.V2.Ingress.Definition`

Ingress-side trigger definition used to normalize webhook and polling inputs.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.Ingress.Definition{
  capability_id: String.t(),
  connector_id: String.t(),
  dedupe_ttl_seconds: pos_integer(),
  signal_source: String.t(),
  signal_type: String.t(),
  source: Jido.Integration.V2.Contracts.trigger_source(),
  trigger_id: String.t(),
  validator: validator() | nil,
  verification: map() | nil
}
```

# `validator`

```elixir
@type validator() :: (map() -&gt; :ok | {:error, term()})
```

# `from_trigger!`

```elixir
@spec from_trigger!(
  String.t(),
  Jido.Integration.V2.TriggerSpec.t(),
  map() | keyword()
) :: t()
```

# `new!`

```elixir
@spec new!(map()) :: t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
