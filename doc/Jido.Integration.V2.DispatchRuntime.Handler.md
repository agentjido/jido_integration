# `Jido.Integration.V2.DispatchRuntime.Handler`

Host-controlled trigger handler registration for async dispatch execution.

# `context`

```elixir
@type context() :: %{
  dispatch: Jido.Integration.V2.DispatchRuntime.Dispatch.t(),
  attempt: pos_integer(),
  run_id: String.t()
}
```

# `execution_opts`

```elixir
@callback execution_opts(Jido.Integration.V2.TriggerRecord.t(), context()) ::
  {:ok, keyword()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
