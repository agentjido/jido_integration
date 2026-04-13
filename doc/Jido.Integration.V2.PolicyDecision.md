# `Jido.Integration.V2.PolicyDecision`

Captures the control-plane admission decision for a run.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.PolicyDecision{
  audit_context: map(),
  execution_policy: map(),
  reasons: [binary()],
  status: (:allowed | :denied | :shed) | binary()
}
```

# `allow`

```elixir
@spec allow(map(), map()) :: t()
```

# `deny`

```elixir
@spec deny([String.t()], map(), map()) :: t()
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

# `shed`

```elixir
@spec shed([String.t()], map(), map()) :: t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
