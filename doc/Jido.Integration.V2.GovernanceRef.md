# `Jido.Integration.V2.GovernanceRef`

Stable reference to governance lineage such as approval, denial, override, rollback, or policy decisions.

# `kind`

```elixir
@type kind() :: :approval | :denial | :override | :rollback | :policy_decision
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.GovernanceRef{
  evidence: [any()],
  id: binary(),
  kind:
    (:approval | :denial | :override | :rollback | :policy_decision) | binary(),
  metadata: map(),
  ref: nil | nil | binary(),
  subject: any()
}
```

# `dump`

```elixir
@spec dump(t()) :: %{
  ref: String.t(),
  kind: kind(),
  id: String.t(),
  subject: map(),
  evidence: [map()],
  metadata: map()
}
```

# `new`

```elixir
@spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
```

# `new!`

```elixir
@spec new!(map() | keyword() | t()) :: t()
```

# `ref`

```elixir
@spec ref(kind(), String.t()) :: String.t()
```

# `schema`

```elixir
@spec schema() :: Zoi.schema()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
