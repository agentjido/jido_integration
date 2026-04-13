# `Jido.Integration.V2.ExecutionGovernanceProjection.Verifier`

Verifies that supplied operational shadow sections still match the Spine compiler.

# `verify`

```elixir
@spec verify(
  Jido.Integration.V2.ExecutionGovernanceProjection.t(),
  map(),
  map(),
  map()
) :: :ok | {:error, :projection_mismatch, map()}
```

# `verify!`

```elixir
@spec verify!(
  Jido.Integration.V2.ExecutionGovernanceProjection.t(),
  map(),
  map(),
  map()
) :: :ok
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
