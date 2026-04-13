# `Jido.Integration.V2.InferenceResult`

Canonical terminal inference outcome projected by the control plane.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.InferenceResult{
  attempt_id: binary(),
  contract_version: binary(),
  endpoint_id: nil | nil | binary(),
  error: nil | nil | map(),
  finish_reason: nil | nil | atom() | binary(),
  metadata: map(),
  run_id: binary(),
  status: (:ok | :error | :cancelled) | binary(),
  stream_id: nil | nil | binary(),
  streaming?: boolean(),
  usage: nil | nil | map()
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
