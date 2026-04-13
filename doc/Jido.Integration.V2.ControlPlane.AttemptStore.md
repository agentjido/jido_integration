# `Jido.Integration.V2.ControlPlane.AttemptStore`

Durable attempt-truth behaviour owned by `control_plane`.

# `fetch_attempt`

```elixir
@callback fetch_attempt(String.t()) :: {:ok, Jido.Integration.V2.Attempt.t()} | :error
```

# `list_attempts`

```elixir
@callback list_attempts(String.t()) :: [Jido.Integration.V2.Attempt.t()]
```

# `put_attempt`

```elixir
@callback put_attempt(Jido.Integration.V2.Attempt.t()) :: :ok | {:error, term()}
```

# `update_attempt`

```elixir
@callback update_attempt(String.t(), atom(), map() | nil, String.t() | nil, keyword()) ::
  :ok | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
