# `Jido.Integration.V2.ExecutionGovernanceProjection`

Spine-owned machine-readable governance projection carried in Brain submissions.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.ExecutionGovernanceProjection{
  authority_ref: map(),
  boundary: map(),
  contract_version: String.t(),
  execution_governance_id: String.t(),
  extensions: map(),
  operations: map(),
  placement: map(),
  resources: map(),
  sandbox: map(),
  topology: map(),
  workspace: map()
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
