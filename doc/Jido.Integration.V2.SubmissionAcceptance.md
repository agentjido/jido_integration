# `Jido.Integration.V2.SubmissionAcceptance`

Durable Spine acceptance receipt for a Brain submission.

# `status`

```elixir
@type status() :: :accepted | :duplicate
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.SubmissionAcceptance{
  accepted_at: DateTime.t(),
  contract_version: String.t(),
  ledger_version: non_neg_integer(),
  status: status(),
  submission_key: Jido.Integration.V2.Contracts.checksum(),
  submission_receipt_ref: String.t()
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

---

*Consult [api-reference.md](api-reference.md) for complete listing*
