# `Jido.Integration.V2.DerivedStateAttachment`

Canonical attachment contract for higher-order derived state.

Higher-order repos persist their own enrichments, memories, lineage, and
scores, but those records must stay anchored to node-local source truth
through explicit subject, evidence, and governance refs.

# `dump_t`

```elixir
@type dump_t() :: %{
  subject: map(),
  evidence_refs: [map()],
  governance_refs: [map()],
  metadata: map()
}
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.DerivedStateAttachment{
  evidence_refs: [any()],
  governance_refs: [any()],
  metadata: map(),
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
