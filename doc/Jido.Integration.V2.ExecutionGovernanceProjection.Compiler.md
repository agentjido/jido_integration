# `Jido.Integration.V2.ExecutionGovernanceProjection.Compiler`

Compiles Spine-owned governance projections into operational shadow sections.

# `shadows`

```elixir
@type shadows() :: %{
  gateway_request: map(),
  runtime_request: map(),
  boundary_request: map()
}
```

# `compile!`

```elixir
@spec compile!(Jido.Integration.V2.ExecutionGovernanceProjection.t()) :: shadows()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
