# `Jido.Integration.V2.BrainIngress.SubmissionLedger`

Durable acceptance ledger for Brain submissions.

# `accept_submission`

```elixir
@callback accept_submission(
  Jido.Integration.V2.BrainInvocation.t(),
  keyword()
) :: {:ok, Jido.Integration.V2.SubmissionAcceptance.t()} | {:error, term()}
```

# `fetch_acceptance`

```elixir
@callback fetch_acceptance(
  String.t(),
  keyword()
) :: {:ok, Jido.Integration.V2.SubmissionAcceptance.t()} | :error
```

# `record_rejection`

```elixir
@callback record_rejection(
  String.t(),
  Jido.Integration.V2.SubmissionRejection.t(),
  keyword()
) ::
  :ok | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
