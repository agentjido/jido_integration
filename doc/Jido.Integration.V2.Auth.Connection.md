# `Jido.Integration.V2.Auth.Connection`

Durable connection truth owned by `auth`.

# `state`

```elixir
@type state() ::
  :installing | :connected | :degraded | :reauth_required | :revoked | :disabled
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.Auth.Connection{
  actor_id: String.t() | nil,
  auth_type: atom(),
  connection_id: String.t(),
  connector_id: String.t(),
  credential_ref_id: String.t() | nil,
  current_credential_id: String.t() | nil,
  current_credential_ref_id: String.t() | nil,
  degraded_reason: String.t() | nil,
  disabled_reason: String.t() | nil,
  external_secret_ref: map() | nil,
  granted_scopes: [String.t()],
  inserted_at: DateTime.t(),
  install_id: String.t() | nil,
  last_refresh_at: DateTime.t() | nil,
  last_refresh_status: atom() | nil,
  last_rotated_at: DateTime.t() | nil,
  lease_fields: [String.t()],
  management_mode: atom() | nil,
  metadata: map(),
  profile_id: String.t() | nil,
  reauth_required_reason: String.t() | nil,
  requested_scopes: [String.t()],
  revocation_reason: String.t() | nil,
  revoked_at: DateTime.t() | nil,
  secret_source: atom() | nil,
  state: state(),
  subject: String.t(),
  tenant_id: String.t(),
  token_expires_at: DateTime.t() | nil,
  updated_at: DateTime.t()
}
```

# `blocked?`

```elixir
@spec blocked?(t()) :: boolean()
```

# `can_transition?`

```elixir
@spec can_transition?(state(), state()) :: boolean()
```

# `new!`

```elixir
@spec new!(map()) :: t()
```

# `validate_state!`

```elixir
@spec validate_state!(state()) :: state()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
