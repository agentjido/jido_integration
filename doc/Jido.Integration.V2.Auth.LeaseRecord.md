# `Jido.Integration.V2.Auth.LeaseRecord`

Durable lease metadata. Secret payload is reconstructed from credential truth.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.Auth.LeaseRecord{
  connection_id: String.t(),
  credential_id: String.t(),
  credential_ref_id: String.t(),
  expires_at: DateTime.t(),
  inserted_at: DateTime.t() | nil,
  issued_at: DateTime.t(),
  lease_id: String.t(),
  metadata: map(),
  payload_keys: [String.t()],
  profile_id: String.t() | nil,
  revoked_at: DateTime.t() | nil,
  scopes: [String.t()],
  subject: String.t()
}
```

# `new!`

```elixir
@spec new!(map()) :: t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
