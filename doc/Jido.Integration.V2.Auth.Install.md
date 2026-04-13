# `Jido.Integration.V2.Auth.Install`

Durable install-session truth owned by `auth`.

# `state`

```elixir
@type state() ::
  :installing
  | :awaiting_callback
  | :completed
  | :expired
  | :cancelled
  | :failed
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.Auth.Install{
  actor_id: String.t(),
  auth_type: atom(),
  callback_received_at: DateTime.t() | nil,
  callback_token: String.t(),
  callback_uri: String.t() | nil,
  cancelled_at: DateTime.t() | nil,
  completed_at: DateTime.t() | nil,
  connection_id: String.t(),
  connector_id: String.t(),
  expires_at: DateTime.t(),
  failure_reason: String.t() | nil,
  flow_kind: atom() | nil,
  granted_scopes: [String.t()],
  inserted_at: DateTime.t(),
  install_id: String.t(),
  metadata: map(),
  pkce_verifier_digest: String.t() | nil,
  profile_id: String.t(),
  reauth_of_connection_id: String.t() | nil,
  requested_scopes: [String.t()],
  state: state(),
  state_token: String.t() | nil,
  subject: String.t(),
  tenant_id: String.t(),
  updated_at: DateTime.t()
}
```

# `expired?`

```elixir
@spec expired?(t(), DateTime.t()) :: boolean()
```

# `new!`

```elixir
@spec new!(map()) :: t()
```

# `review_safe`

```elixir
@spec review_safe(t()) :: t()
```

Drop or redact auth-control callback material before exposing install truth on
review-facing read surfaces.

# `validate_state!`

```elixir
@spec validate_state!(state()) :: state()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
