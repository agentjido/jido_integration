# `Jido.Integration.V2.BrainIngress`

Durable Brain-to-Spine invocation intake.

# `runtime_inputs`

```elixir
@type runtime_inputs() :: %{
  workspace_root: String.t() | nil,
  file_scope: String.t() | nil,
  routing_hints: map(),
  execution_family: String.t(),
  target_kind: String.t(),
  allowed_tools: [String.t()]
}
```

# `accept_invocation`

```elixir
@spec accept_invocation(
  Jido.Integration.V2.BrainInvocation.t() | map(),
  keyword()
) ::
  {:ok, Jido.Integration.V2.SubmissionAcceptance.t(),
   Jido.Integration.V2.Gateway.t(), runtime_inputs()}
  | {:error, Jido.Integration.V2.SubmissionRejection.t()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
