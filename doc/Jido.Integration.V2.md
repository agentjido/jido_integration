# `Jido.Integration.V2`

Public facade package for the greenfield `jido_integration_v2` platform.

The tooling workspace lives at the repository root. Runtime entrypoints live
here and delegate to the child packages that implement the control plane,
auth boundary, and shared contracts.

The public surface includes:

- deterministic connector and capability discovery through `connectors/0`,
  `capabilities/0`, `fetch_connector/1`, `fetch_capability/1`,
  `catalog_entries/0`, and `projected_catalog_entries/0`
- durable auth lifecycle operations through `start_install/3`,
  `resolve_install_callback/1`, `complete_install/2`, `fetch_install/1`,
  `installs/1`, `cancel_install/2`, `expire_install/2`,
  `reauthorize_connection/2`, `connection_status/1`, `connections/1`,
  `request_lease/2`, `rotate_connection/2`, and `revoke_connection/2`
- typed invocation through `InvocationRequest` and `invoke/1`
- direct invocation through `invoke/3` and retry of accepted or failed runs
  through `execute_run/3`
- read-only operator review helpers through `targets/1`,
  `compatible_targets_for/2`, and `review_packet/2`

Public invocation binds auth through `connection_id` when a capability
requires a durable connection. Credential resolution and lease issuance stay
behind the auth and control-plane seam. The shared operator helpers remain
read-only projections over durable auth and control-plane truth rather than
becoming a second store, policy engine, or runtime owner.

Session and stream execution stay above the provider-neutral runtime basis.
Published `runtime.driver` values name the `jido_runtime_control`
`Jido.RuntimeControl` driver ids such as `asm`; that path resolves through
`Jido.Integration.V2.AsmRuntimeBridge.RuntimeControlDriver` into
`agent_session_manager`, with `cli_subprocess_core` below ASM. Durable auth,
control-plane, and operator truth still remain owned by `jido_integration`.

# `announce_target`

```elixir
@spec announce_target(Jido.Integration.V2.TargetDescriptor.t()) ::
  :ok | {:error, term()}
```

Upsert a target announcement into durable control-plane truth.

# `cancel_install`

```elixir
@spec cancel_install(String.t(), map()) ::
  {:ok,
   %{
     install: Jido.Integration.V2.Auth.Install.t(),
     connection: Jido.Integration.V2.Auth.Connection.t()
   }}
  | {:error, term()}
```

Cancel an in-flight install or reauth attempt.

# `capabilities`

```elixir
@spec capabilities() :: [Jido.Integration.V2.Capability.t()]
```

List all registered capabilities.

# `catalog_entries`

```elixir
@spec catalog_entries() :: [map()]
```

Summarize connector catalog entries for operator-facing discovery.

# `compatible_targets`

```elixir
@spec compatible_targets(map()) :: [
  %{
    target: Jido.Integration.V2.TargetDescriptor.t(),
    negotiated_versions: map()
  }
]
```

Return targets compatible with the requested capability/runtime/version posture.

# `compatible_targets_for`

```elixir
@spec compatible_targets_for(String.t(), map()) ::
  {:ok, [map()]} | {:error, :unknown_capability | :unknown_connector}
```

Derive authored-compatible target matches for a capability.

# `complete_install`

```elixir
@spec complete_install(String.t(), map()) ::
  {:ok,
   %{
     install: Jido.Integration.V2.Auth.Install.t(),
     connection: Jido.Integration.V2.Auth.Connection.t(),
     credential_ref: Jido.Integration.V2.CredentialRef.t()
   }}
  | {:error, term()}
```

Complete an install and bind durable credential truth to the connection.

# `connection_status`

```elixir
@spec connection_status(String.t()) ::
  {:ok, Jido.Integration.V2.Auth.Connection.t()} | {:error, :unknown_connection}
```

Fetch safe connection status through the host-facing auth boundary.

# `connections`

```elixir
@spec connections(map()) :: [Jido.Integration.V2.Auth.Connection.t()]
```

List durable connections through the shared operator surface.

# `connectors`

```elixir
@spec connectors() :: [Jido.Integration.V2.Manifest.t()]
```

List all registered connector manifests in deterministic connector-id order.

# `events`

```elixir
@spec events(String.t()) :: [Jido.Integration.V2.Event.t()]
```

List canonical events for a run.

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

Re-execute an accepted or failed run as a new attempt through the control
plane.

Completed, denied, and shed runs are terminal and are rejected without
mutating durable run truth.

# `expire_install`

```elixir
@spec expire_install(String.t(), map()) ::
  {:ok,
   %{
     install: Jido.Integration.V2.Auth.Install.t(),
     connection: Jido.Integration.V2.Auth.Connection.t()
   }}
  | {:error, term()}
```

Mark an in-flight install as expired and reconcile connection state.

# `fetch_artifact`

```elixir
@spec fetch_artifact(String.t()) ::
  {:ok, Jido.Integration.V2.ArtifactRef.t()} | :error
```

Fetch a durable artifact reference by id.

# `fetch_attempt`

```elixir
@spec fetch_attempt(String.t()) :: {:ok, Jido.Integration.V2.Attempt.t()} | :error
```

Fetch a previously recorded attempt.

# `fetch_capability`

```elixir
@spec fetch_capability(String.t()) ::
  {:ok, Jido.Integration.V2.Capability.t()} | {:error, :unknown_capability}
```

Fetch a registered capability by capability id.

# `fetch_connector`

```elixir
@spec fetch_connector(String.t()) ::
  {:ok, Jido.Integration.V2.Manifest.t()} | {:error, :unknown_connector}
```

Fetch a registered connector manifest by connector id.

# `fetch_install`

```elixir
@spec fetch_install(String.t()) ::
  {:ok, Jido.Integration.V2.Auth.Install.t()} | {:error, :unknown_install}
```

Fetch a durable install session by id.

# `fetch_run`

```elixir
@spec fetch_run(String.t()) :: {:ok, Jido.Integration.V2.Run.t()} | :error
```

Fetch a previously recorded run.

# `fetch_target`

```elixir
@spec fetch_target(String.t()) ::
  {:ok, Jido.Integration.V2.TargetDescriptor.t()} | :error
```

Fetch a durable target descriptor by id.

# `installs`

```elixir
@spec installs(map()) :: [Jido.Integration.V2.Auth.Install.t()]
```

List durable installs through the shared operator surface.

# `invoke`

```elixir
@spec invoke(Jido.Integration.V2.InvocationRequest.t()) ::
  {:ok,
   %{
     run: Jido.Integration.V2.Run.t(),
     attempt: Jido.Integration.V2.Attempt.t(),
     output: map()
   }}
  | {:error, Jido.Integration.V2.ControlPlane.invoke_preflight_error()}
  | {:error,
     %{
       reason: term(),
       run: Jido.Integration.V2.Run.t(),
       attempt: Jido.Integration.V2.Attempt.t() | nil,
       policy_decision: Jido.Integration.V2.PolicyDecision.t() | nil
     }}
```

Invoke a capability through the control plane using a typed request.

# `invoke`

```elixir
@spec invoke(String.t(), map(), keyword()) ::
  {:ok,
   %{
     run: Jido.Integration.V2.Run.t(),
     attempt: Jido.Integration.V2.Attempt.t(),
     output: map()
   }}
  | {:error, Jido.Integration.V2.ControlPlane.invoke_preflight_error()}
  | {:error,
     %{
       reason: term(),
       run: Jido.Integration.V2.Run.t(),
       attempt: Jido.Integration.V2.Attempt.t() | nil,
       policy_decision: Jido.Integration.V2.PolicyDecision.t() | nil
     }}
```

Invoke a capability through the control plane.

Public callers bind auth with `:connection_id` when the capability requires
a durable connection.

# `invoke_inference`

```elixir
@spec invoke_inference(
  Jido.Integration.V2.InferenceRequest.t() | map() | keyword(),
  keyword()
) :: {:ok, map()} | {:error, term()}
```

Invoke one inference request through the public control-plane facade.

# `projected_catalog_entries`

```elixir
@spec projected_catalog_entries() :: [map()]
```

Export the common projected consumer surface with generated identities and
JSON Schema payloads for tools and docs consumers.

# `reauthorize_connection`

```elixir
@spec reauthorize_connection(String.t(), map()) ::
  {:ok,
   %{
     install: Jido.Integration.V2.Auth.Install.t(),
     connection: Jido.Integration.V2.Auth.Connection.t(),
     session_state: map()
   }}
  | {:error, term()}
```

Start a reauth flow against an existing durable connection.

# `record_artifact`

```elixir
@spec record_artifact(Jido.Integration.V2.ArtifactRef.t()) :: :ok | {:error, term()}
```

Record an artifact reference emitted by the control plane or runtime.

# `register_connector`

```elixir
@spec register_connector(module()) :: :ok | {:error, term()}
```

Register a connector manifest with the control plane.

# `request_lease`

```elixir
@spec request_lease(String.t(), map()) ::
  {:ok, Jido.Integration.V2.CredentialLease.t()} | {:error, term()}
```

Issue a short-lived lease for runtime execution.

# `reset!`

```elixir
@spec reset!() :: :ok
```

Reset in-memory state for tests and local exploration.

# `resolve_install_callback`

```elixir
@spec resolve_install_callback(map()) ::
  {:ok,
   %{
     install: Jido.Integration.V2.Auth.Install.t(),
     connection: Jido.Integration.V2.Auth.Connection.t()
   }}
  | {:error, term()}
```

Resolve and validate a hosted callback against durable install truth.

# `review_packet`

```elixir
@spec review_packet(String.t(), map()) ::
  {:ok, map()}
  | {:error,
     :unknown_run | :unknown_attempt | :unknown_capability | :unknown_connector}
```

Assemble a shared review packet from durable auth and control-plane truth.

The packet keeps its read-side metadata explicit through `SubjectRef`,
`EvidenceRef`, and `GovernanceRef`-shaped metadata entries while leaving the
underlying source facts where they already live. Auth install context in the
packet is review-safe and redacts callback, PKCE, and redirect material.

# `revoke_connection`

```elixir
@spec revoke_connection(String.t(), map()) ::
  {:ok, Jido.Integration.V2.Auth.Connection.t()} | {:error, term()}
```

Revoke a connection and invalidate future lease use.

# `rotate_connection`

```elixir
@spec rotate_connection(String.t(), map()) ::
  {:ok,
   %{
     connection: Jido.Integration.V2.Auth.Connection.t(),
     credential_ref: Jido.Integration.V2.CredentialRef.t()
   }}
  | {:error, term()}
```

Rotate a connection's durable secret truth without changing its credential ref.

# `run_artifacts`

```elixir
@spec run_artifacts(String.t()) :: [Jido.Integration.V2.ArtifactRef.t()]
```

List durable artifact references for a run.

# `start_install`

```elixir
@spec start_install(String.t(), String.t(), map()) ::
  {:ok,
   %{
     install: Jido.Integration.V2.Auth.Install.t(),
     connection: Jido.Integration.V2.Auth.Connection.t(),
     session_state: map()
   }}
  | {:error, term()}
```

Start an install flow through the auth subsystem.

# `targets`

```elixir
@spec targets(map()) :: [Jido.Integration.V2.TargetDescriptor.t()]
```

List durable target descriptors through the shared operator surface.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
