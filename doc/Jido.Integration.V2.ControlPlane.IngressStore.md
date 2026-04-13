# `Jido.Integration.V2.ControlPlane.IngressStore`

Durable ingress-truth behaviour owned by `control_plane`.

# `fetch_checkpoint`

```elixir
@callback fetch_checkpoint(String.t(), String.t(), String.t(), String.t()) ::
  {:ok, Jido.Integration.V2.TriggerCheckpoint.t()} | :error
```

# `fetch_trigger`

```elixir
@callback fetch_trigger(String.t(), String.t(), String.t(), String.t()) ::
  {:ok, Jido.Integration.V2.TriggerRecord.t()} | :error
```

# `list_run_triggers`

```elixir
@callback list_run_triggers(String.t()) :: [Jido.Integration.V2.TriggerRecord.t()]
```

# `put_checkpoint`

```elixir
@callback put_checkpoint(Jido.Integration.V2.TriggerCheckpoint.t()) ::
  :ok | {:error, term()}
```

# `put_trigger`

```elixir
@callback put_trigger(Jido.Integration.V2.TriggerRecord.t()) :: :ok | {:error, term()}
```

# `reserve_dedupe`

```elixir
@callback reserve_dedupe(
  tenant_id :: String.t(),
  connector_id :: String.t(),
  trigger_id :: String.t(),
  dedupe_key :: String.t(),
  expires_at :: DateTime.t()
) :: :ok | {:error, :duplicate | term()}
```

# `rollback`

```elixir
@callback rollback(term()) :: no_return()
```

# `transaction`

```elixir
@callback transaction((-&gt; term())) :: term()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
