# `Jido.Integration.V2.DispatchRuntime`

Async trigger dispatch runtime with durable transport-state recovery.

# `execute_result`

```elixir
@type execute_result() ::
  {:ok, %{run: Jido.Integration.V2.Run.t(), attempt: map(), output: map()}}
  | {:error,
     %{
       reason: term(),
       run: Jido.Integration.V2.Run.t(),
       attempt: map() | nil,
       policy_decision: map() | nil
     }}
  | {:error, term()}
```

# `runtime_state`

```elixir
@type runtime_state() :: %{
  storage_path: String.t(),
  task_supervisor: pid(),
  dispatches: %{
    optional(String.t()) =&gt; Jido.Integration.V2.DispatchRuntime.Dispatch.t()
  },
  handlers: %{optional(String.t()) =&gt; module()},
  timers: %{optional(String.t()) =&gt; reference()},
  tasks: %{optional(String.t()) =&gt; pid()},
  max_attempts: pos_integer(),
  backoff_base_ms: pos_integer(),
  backoff_cap_ms: pos_integer()
}
```

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `enqueue`

```elixir
@spec enqueue(GenServer.server(), Jido.Integration.V2.TriggerRecord.t(), keyword()) ::
  {:ok,
   %{
     status: :accepted | :duplicate,
     dispatch: Jido.Integration.V2.DispatchRuntime.Dispatch.t(),
     run: Jido.Integration.V2.Run.t()
   }}
  | {:error, term()}
```

# `enqueue`

```elixir
@spec enqueue(
  GenServer.server(),
  Jido.Integration.V2.TriggerRecord.t(),
  Jido.Integration.V2.TriggerCheckpoint.t(),
  keyword()
) ::
  {:ok,
   %{
     status: :accepted | :duplicate,
     dispatch: Jido.Integration.V2.DispatchRuntime.Dispatch.t(),
     run: Jido.Integration.V2.Run.t()
   }}
  | {:error, term()}
```

# `fetch_dispatch`

```elixir
@spec fetch_dispatch(GenServer.server(), String.t()) ::
  {:ok, Jido.Integration.V2.DispatchRuntime.Dispatch.t()} | :error
```

# `list_dispatches`

```elixir
@spec list_dispatches(
  GenServer.server(),
  keyword()
) :: [Jido.Integration.V2.DispatchRuntime.Dispatch.t()]
```

# `register_handler`

```elixir
@spec register_handler(GenServer.server(), String.t(), module()) ::
  :ok | {:error, term()}
```

# `replay`

```elixir
@spec replay(GenServer.server(), String.t()) ::
  {:ok, Jido.Integration.V2.DispatchRuntime.Dispatch.t()} | {:error, term()}
```

# `start_link`

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
