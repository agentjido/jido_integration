# `Jido.Integration.V2.SubmissionIdentity`

Spine-owned stable identity for a durable Brain submission.

# `submission_family`

```elixir
@type submission_family() :: :invocation | :boundary | :projection | :query
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.SubmissionIdentity{
  authority_decision_id: String.t(),
  causal_group_id: String.t(),
  contract_version: String.t(),
  execution_governance_id: String.t(),
  execution_intent_family: String.t(),
  extensions: map(),
  invocation_request_id: String.t(),
  request_id: String.t(),
  selected_step_id: String.t(),
  session_id: String.t(),
  submission_family: submission_family(),
  target_id: String.t(),
  target_kind: String.t(),
  tenant_id: String.t()
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

# `submission_key`

```elixir
@spec submission_key(t()) :: Jido.Integration.V2.Contracts.checksum()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
