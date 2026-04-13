# `Jido.Integration.V2.BrainInvocation`

Durable Brain-to-Spine invocation handoff packet.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.BrainInvocation{
  actor_id: String.t(),
  allowed_operations: [String.t()],
  authority_payload: Jido.Integration.V2.AuthorityAuditEnvelope.t(),
  authority_payload_hash: Jido.Integration.V2.Contracts.checksum(),
  boundary_request: map(),
  contract_version: String.t(),
  execution_governance_payload:
    Jido.Integration.V2.ExecutionGovernanceProjection.t(),
  execution_governance_payload_hash: Jido.Integration.V2.Contracts.checksum(),
  execution_intent: map(),
  execution_intent_family: String.t(),
  extensions: map(),
  gateway_request: map(),
  request_id: String.t(),
  runtime_class: Jido.Integration.V2.Contracts.runtime_class(),
  runtime_request: map(),
  session_id: String.t(),
  submission_identity: Jido.Integration.V2.SubmissionIdentity.t(),
  submission_key: Jido.Integration.V2.Contracts.checksum(),
  target_id: String.t(),
  target_kind: String.t(),
  tenant_id: String.t(),
  trace_id: String.t()
}
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

---

*Consult [api-reference.md](api-reference.md) for complete listing*
