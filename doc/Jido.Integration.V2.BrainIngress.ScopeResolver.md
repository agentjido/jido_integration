# `Jido.Integration.V2.BrainIngress.ScopeResolver`

Resolves logical workspace references into concrete runtime paths.

# `resolve`

```elixir
@callback resolve(String.t() | nil, String.t() | nil, keyword()) ::
  {:ok, %{workspace_root: String.t() | nil, file_scope: String.t() | nil}}
  | {:error, {:scope_unresolvable, String.t() | nil}}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
