# `Jido.Integration.V2.ControlPlane.RunStore`

Durable run-truth behaviour owned by `control_plane`.

# `fetch_run`

```elixir
@callback fetch_run(String.t()) :: {:ok, Jido.Integration.V2.Run.t()} | :error
```

# `put_run`

```elixir
@callback put_run(Jido.Integration.V2.Run.t()) :: :ok | {:error, term()}
```

# `update_run`

```elixir
@callback update_run(String.t(), atom(), map() | nil) :: :ok | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
