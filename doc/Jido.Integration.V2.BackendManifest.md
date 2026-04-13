# `Jido.Integration.V2.BackendManifest`

Declares what a runtime backend can expose to the inference control plane.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.BackendManifest{
  backend: atom() | binary(),
  capabilities: map(),
  contract_version: binary(),
  management_modes: [
    (:provider_managed | :jido_managed | :externally_managed) | binary()
  ],
  metadata: map(),
  protocols: [:openai_chat_completions | binary()],
  resource_profile: map(),
  runtime_kind: (:task | :service) | binary(),
  startup_kind: nil | nil | (:spawned | :attach_existing_service) | binary(),
  supported_surfaces: [atom() | binary()]
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
