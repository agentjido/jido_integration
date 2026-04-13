# `Jido.Integration.V2.WebhookRouter.Route`

Durable hosted-webhook route metadata.

# `callback_topology`

```elixir
@type callback_topology() :: :dynamic_per_install | :static_per_app
```

Explicit hosted callback topology for a registered route.

# `secret_ref`

```elixir
@type secret_ref() :: %{
  credential_ref: Jido.Integration.V2.CredentialRef.t(),
  secret_key: String.t()
}
```

# `status`

```elixir
@type status() :: :active | :disabled | :revoked
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.WebhookRouter.Route{
  callback_topology: callback_topology(),
  capability_id: String.t(),
  connection_id: String.t() | nil,
  connector_id: String.t(),
  dedupe_ttl_seconds: pos_integer(),
  delivery_id_headers: [String.t()],
  inserted_at: DateTime.t(),
  install_id: String.t() | nil,
  revision: pos_integer(),
  route_id: String.t(),
  signal_source: String.t(),
  signal_type: String.t(),
  status: status(),
  tenant_id: String.t() | nil,
  tenant_resolution: map(),
  tenant_resolution_keys: [String.t()],
  trigger_id: String.t(),
  updated_at: DateTime.t(),
  validator: validator_ref(),
  verification: verification() | nil
}
```

# `validator_ref`

```elixir
@type validator_ref() :: {module(), atom()} | nil
```

# `verification`

```elixir
@type verification() :: %{
  optional(:algorithm) =&gt; atom(),
  optional(:signature_header) =&gt; String.t(),
  optional(:secret) =&gt; String.t(),
  optional(:secret_ref) =&gt; secret_ref()
}
```

# `active?`

```elixir
@spec active?(t()) :: boolean()
```

# `identity_key`

```elixir
@spec identity_key(t()) :: term()
```

# `new!`

```elixir
@spec new!(map()) :: t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
