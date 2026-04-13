# `Jido.Integration.V2.DirectRuntime`

Executes direct capabilities through `Jido.Action` modules.

# `runtime_result`

```elixir
@type runtime_result() :: Jido.Integration.V2.RuntimeResult.t()
```

# `execute`

```elixir
@spec execute(Jido.Integration.V2.Capability.t(), map(), map()) ::
  {:ok, runtime_result()} | {:error, term(), runtime_result()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
