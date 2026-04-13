# `Jido.Integration.V2.CompatibilityResult`

Typed compatibility outcome for an admitted inference route.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.CompatibilityResult{
  compatible?: boolean(),
  contract_version: binary(),
  metadata: map(),
  missing_requirements: [atom() | binary()],
  reason: atom() | binary(),
  resolved_management_mode:
    nil
    | nil
    | (:provider_managed | :jido_managed | :externally_managed)
    | binary(),
  resolved_protocol: nil | nil | atom() | binary(),
  resolved_runtime_kind: nil | nil | (:client | :task | :service) | binary(),
  warnings: [atom() | binary()]
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
