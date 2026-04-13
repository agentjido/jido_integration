# `Jido.Integration.V2.InferenceRequest`

Normalized admitted inference intent before target resolution.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.InferenceRequest{
  contract_version: binary(),
  messages: [map()],
  metadata: map(),
  model_preference: nil | nil | map(),
  operation: (:generate_text | :stream_text) | binary(),
  output_constraints: map(),
  prompt: nil | nil | binary(),
  request_id: binary(),
  stream?: boolean(),
  target_preference: nil | nil | map(),
  tool_policy: map()
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
