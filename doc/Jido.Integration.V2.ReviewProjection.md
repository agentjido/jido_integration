# `Jido.Integration.V2.ReviewProjection`

Contracts-only northbound review projection carried in review packet metadata.

# `dump_t`

```elixir
@type dump_t() :: %{
  schema_version: String.t(),
  projection: String.t(),
  packet_ref: String.t(),
  subject: map(),
  selected_attempt: map() | nil,
  evidence_refs: [map()],
  governance_refs: [map()]
}
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.ReviewProjection{
  evidence_refs: [any()],
  governance_refs: [any()],
  packet_ref: binary(),
  projection: binary(),
  schema_version: binary(),
  selected_attempt: nil | nil | any(),
  subject: any()
}
```

# `dump`

```elixir
@spec dump(t()) :: dump_t()
```

# `new`

```elixir
@spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
```

# `new!`

```elixir
@spec new!(map() | keyword() | t()) :: t()
```

# `schema`

```elixir
@spec schema() :: Zoi.schema()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
