# `Jido.Integration.V2.SubmissionRejection`

Typed Spine rejection for a Brain submission.

# `rejection_family`

```elixir
@type rejection_family() ::
  :invalid_submission
  | :projection_mismatch
  | :scope_unresolvable
  | :policy_denied
  | :policy_shed
  | :unsupported_target
  | :capacity_exhausted
```

# `retry_class`

```elixir
@type retry_class() :: :never | :after_redecision | :retryable
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.SubmissionRejection{
  contract_version: String.t(),
  details: map(),
  reason_code: String.t(),
  redecision_required: boolean(),
  rejected_at: DateTime.t(),
  rejection_family: rejection_family(),
  retry_class: retry_class(),
  submission_key: Jido.Integration.V2.Contracts.checksum()
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
