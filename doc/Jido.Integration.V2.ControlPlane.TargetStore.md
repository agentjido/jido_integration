# `Jido.Integration.V2.ControlPlane.TargetStore`

Durable target-descriptor truth owned by `control_plane`.

# `fetch_target_descriptor`

```elixir
@callback fetch_target_descriptor(String.t()) ::
  {:ok, Jido.Integration.V2.TargetDescriptor.t()} | :error
```

# `list_target_descriptors`

```elixir
@callback list_target_descriptors() :: [Jido.Integration.V2.TargetDescriptor.t()]
```

# `put_target_descriptor`

```elixir
@callback put_target_descriptor(Jido.Integration.V2.TargetDescriptor.t()) ::
  :ok | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
