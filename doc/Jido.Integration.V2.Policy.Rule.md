# `Jido.Integration.V2.Policy.Rule`

Behaviour for admission rules.

# `evaluate`

```elixir
@callback evaluate(
  Jido.Integration.V2.Capability.t(),
  Jido.Integration.V2.Credential.t(),
  map(),
  map()
) ::
  :ok | {:deny, [String.t()]} | {:shed, [String.t()]}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
