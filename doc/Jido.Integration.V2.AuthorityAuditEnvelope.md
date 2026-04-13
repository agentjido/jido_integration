# `Jido.Integration.V2.AuthorityAuditEnvelope`

Spine-owned machine-readable authority audit payload derived from the Brain packet.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.AuthorityAuditEnvelope{
  approval_profile: String.t(),
  boundary_class: String.t(),
  contract_version: String.t(),
  decision_hash: String.t(),
  decision_id: String.t(),
  egress_profile: String.t(),
  extensions: map(),
  policy_version: String.t(),
  request_id: String.t(),
  resource_profile: String.t(),
  tenant_id: String.t(),
  trust_profile: String.t(),
  workspace_profile: String.t()
}
```

# `contract_version`

```elixir
@spec contract_version() :: String.t()
```

# `dump`

```elixir
@spec dump(t()) :: map()
```

# `new`

```elixir
@spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
```

# `new!`

```elixir
@spec new!(t() | map() | keyword()) :: t()
```

# `payload_hash`

```elixir
@spec payload_hash(t()) :: Jido.Integration.V2.Contracts.checksum()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
