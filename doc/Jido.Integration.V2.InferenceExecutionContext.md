# `Jido.Integration.V2.InferenceExecutionContext`

Control-plane context attached to an admitted inference attempt.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.InferenceExecutionContext{
  attempt_id: binary(),
  authority_ref: nil | nil | binary(),
  authority_source: (:jido_integration | :jido_os | :external) | binary(),
  boundary_ref: nil | nil | binary(),
  contract_version: binary(),
  credential_scope: map(),
  decision_ref: nil | nil | binary(),
  metadata: map(),
  network_policy: map(),
  observability: map(),
  replay: map(),
  run_id: binary(),
  streaming_policy: map()
}
```

# `dump`

```elixir
@spec dump(t()) :: map()
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
