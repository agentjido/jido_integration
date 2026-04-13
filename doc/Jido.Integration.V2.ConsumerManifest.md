# `Jido.Integration.V2.ConsumerManifest`

Declares what an inference consumer can accept from a runtime route.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.ConsumerManifest{
  accepted_management_modes: [
    (:provider_managed | :jido_managed | :externally_managed) | binary()
  ],
  accepted_protocols: [atom() | binary()],
  accepted_runtime_kinds: [(:client | :task | :service) | binary()],
  constraints: map(),
  consumer: atom() | binary(),
  contract_version: binary(),
  metadata: map(),
  optional_capabilities: map(),
  required_capabilities: map()
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
