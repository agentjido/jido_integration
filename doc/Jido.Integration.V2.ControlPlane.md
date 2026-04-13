# `Jido.Integration.V2.ControlPlane`

Connector registry plus canonical run/attempt/event ledger.

The control plane owns deterministic connector and capability discovery as
well as the stable invocation boundary that powers the public facade.

# `invoke_preflight_error`

```elixir
@type invoke_preflight_error() ::
  :unknown_capability
  | :connection_required
  | :unknown_connection
  | :unknown_credential
  | :credential_subject_mismatch
  | :credential_expired
  | :connection_installing
  | :connection_disabled
  | :connection_revoked
  | :reauth_required
```

# `admit_trigger`

```elixir
@spec admit_trigger(
  Jido.Integration.V2.TriggerRecord.t(),
  keyword()
) ::
  {:ok,
   %{
     status: :accepted | :duplicate,
     trigger: Jido.Integration.V2.TriggerRecord.t(),
     run: Jido.Integration.V2.Run.t()
   }}
  | {:error, term()}
```

# `announce_target`

```elixir
@spec announce_target(Jido.Integration.V2.TargetDescriptor.t()) ::
  :ok | {:error, term()}
```

# `attempts`

```elixir
@spec attempts(String.t()) :: [Jido.Integration.V2.Attempt.t()]
```

# `capabilities`

```elixir
@spec capabilities() :: [Jido.Integration.V2.Capability.t()]
```

# `compatible_targets`

```elixir
@spec compatible_targets(map()) :: [
  %{
    target: Jido.Integration.V2.TargetDescriptor.t(),
    negotiated_versions: map()
  }
]
```

# `connectors`

```elixir
@spec connectors() :: [Jido.Integration.V2.Manifest.t()]
```

# `events`

```elixir
@spec events(String.t()) :: [Jido.Integration.V2.Event.t()]
```

# `execute_run`

```elixir
@spec execute_run(String.t(), pos_integer(), keyword()) ::
  {:ok,
   %{
     run: Jido.Integration.V2.Run.t(),
     attempt: Jido.Integration.V2.Attempt.t(),
     output: map()
   }}
  | {:error,
     %{
       reason: term(),
       run: Jido.Integration.V2.Run.t(),
       attempt: Jido.Integration.V2.Attempt.t() | nil,
       policy_decision: Jido.Integration.V2.PolicyDecision.t() | nil
     }}
  | {:error, :unknown_run | {:unknown_capability, String.t()}}
```

# `fetch_artifact`

```elixir
@spec fetch_artifact(String.t()) ::
  {:ok, Jido.Integration.V2.ArtifactRef.t()} | :error
```

# `fetch_attempt`

```elixir
@spec fetch_attempt(String.t()) :: {:ok, Jido.Integration.V2.Attempt.t()} | :error
```

# `fetch_capability`

```elixir
@spec fetch_capability(String.t()) ::
  {:ok, Jido.Integration.V2.Capability.t()} | {:error, :unknown_capability}
```

# `fetch_connector`

```elixir
@spec fetch_connector(String.t()) ::
  {:ok, Jido.Integration.V2.Manifest.t()} | {:error, :unknown_connector}
```

# `fetch_run`

```elixir
@spec fetch_run(String.t()) :: {:ok, Jido.Integration.V2.Run.t()} | :error
```

# `fetch_target`

```elixir
@spec fetch_target(String.t()) ::
  {:ok, Jido.Integration.V2.TargetDescriptor.t()} | :error
```

# `fetch_trigger`

```elixir
@spec fetch_trigger(String.t(), String.t(), String.t(), String.t()) ::
  {:ok, Jido.Integration.V2.TriggerRecord.t()} | :error
```

# `fetch_trigger_checkpoint`

```elixir
@spec fetch_trigger_checkpoint(String.t(), String.t(), String.t(), String.t()) ::
  {:ok, Jido.Integration.V2.TriggerCheckpoint.t()} | :error
```

# `inference_capability_id`

```elixir
@spec inference_capability_id() :: String.t()
```

# `invoke`

```elixir
@spec invoke(Jido.Integration.V2.InvocationRequest.t()) ::
  {:ok,
   %{
     run: Jido.Integration.V2.Run.t(),
     attempt: Jido.Integration.V2.Attempt.t(),
     output: map()
   }}
  | {:error, invoke_preflight_error()}
  | {:error,
     %{
       reason: term(),
       run: Jido.Integration.V2.Run.t(),
       attempt: Jido.Integration.V2.Attempt.t() | nil,
       policy_decision: Jido.Integration.V2.PolicyDecision.t() | nil
     }}
```

# `invoke`

```elixir
@spec invoke(String.t(), map(), keyword()) ::
  {:ok,
   %{
     run: Jido.Integration.V2.Run.t(),
     attempt: Jido.Integration.V2.Attempt.t(),
     output: map()
   }}
  | {:error, invoke_preflight_error()}
  | {:error,
     %{
       reason: term(),
       run: Jido.Integration.V2.Run.t(),
       attempt: Jido.Integration.V2.Attempt.t() | nil,
       policy_decision: Jido.Integration.V2.PolicyDecision.t() | nil
     }}
```

# `invoke_inference`

```elixir
@spec invoke_inference(
  Jido.Integration.V2.InferenceRequest.t() | map() | keyword(),
  keyword()
) :: {:ok, map()} | {:error, term()}
```

Public inference entrypoint for the control plane.

# `put_trigger_checkpoint`

```elixir
@spec put_trigger_checkpoint(Jido.Integration.V2.TriggerCheckpoint.t()) ::
  :ok | {:error, term()}
```

# `record_artifact`

```elixir
@spec record_artifact(Jido.Integration.V2.ArtifactRef.t()) :: :ok | {:error, term()}
```

# `record_inference_attempt`

```elixir
@spec record_inference_attempt(map()) ::
  {:ok,
   %{run: Jido.Integration.V2.Run.t(), attempt: Jido.Integration.V2.Attempt.t()}}
  | {:error, Exception.t() | term()}
```

# `record_rejected_trigger`

```elixir
@spec record_rejected_trigger(Jido.Integration.V2.TriggerRecord.t(), term()) ::
  {:ok, Jido.Integration.V2.TriggerRecord.t()} | {:error, term()}
```

# `register_connector`

```elixir
@spec register_connector(module()) :: :ok | {:error, term()}
```

# `reset!`

```elixir
@spec reset!() :: :ok
```

# `run_artifacts`

```elixir
@spec run_artifacts(String.t()) :: [Jido.Integration.V2.ArtifactRef.t()]
```

# `run_triggers`

```elixir
@spec run_triggers(String.t()) :: [Jido.Integration.V2.TriggerRecord.t()]
```

# `targets`

```elixir
@spec targets(map()) :: [Jido.Integration.V2.TargetDescriptor.t()]
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
