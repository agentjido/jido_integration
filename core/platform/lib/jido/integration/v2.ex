defmodule Jido.Integration.V2 do
  @moduledoc """
  Public facade package for the greenfield `jido_integration_v2` platform.

  The tooling workspace lives at the repository root. Runtime entrypoints live
  here and delegate to the child packages that implement the control plane,
  auth boundary, and shared contracts.

  The public surface includes:

  - deterministic connector and capability discovery through `connectors/0`,
    `capabilities/0`, `fetch_connector/1`, `fetch_capability/1`,
    `catalog_entries/0`, and `projected_catalog_entries/0`
  - durable auth lifecycle operations through `start_install/3`,
    `complete_install/2`, `fetch_install/1`, `installs/1`,
    `connection_status/1`, `connections/1`, `request_lease/2`,
    `rotate_connection/2`, and `revoke_connection/2`
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
  Published `runtime.driver` values name the `/home/home/p/g/n/jido_harness`
  `Jido.Harness` driver ids such as `asm`; that path resolves through
  `Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver` into
  `/home/home/p/g/n/agent_session_manager`, with
  `/home/home/p/g/n/cli_subprocess_core` below ASM. Durable auth,
  control-plane, and operator truth still remain owned by `jido_integration`.
  """

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.InvocationRequest
  alias Jido.Integration.V2.Operator
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.TargetDescriptor

  @doc """
  Register a connector manifest with the control plane.
  """
  @spec register_connector(module()) :: :ok | {:error, term()}
  defdelegate register_connector(connector), to: ControlPlane

  @doc """
  List all registered capabilities.
  """
  @spec capabilities() :: [Jido.Integration.V2.Capability.t()]
  defdelegate capabilities(), to: ControlPlane

  @doc """
  List all registered connector manifests in deterministic connector-id order.
  """
  @spec connectors() :: [Jido.Integration.V2.Manifest.t()]
  defdelegate connectors(), to: ControlPlane

  @doc """
  Fetch a registered connector manifest by connector id.
  """
  @spec fetch_connector(String.t()) ::
          {:ok, Jido.Integration.V2.Manifest.t()} | {:error, :unknown_connector}
  defdelegate fetch_connector(connector_id), to: ControlPlane

  @doc """
  Fetch a registered capability by capability id.
  """
  @spec fetch_capability(String.t()) ::
          {:ok, Jido.Integration.V2.Capability.t()} | {:error, :unknown_capability}
  defdelegate fetch_capability(capability_id), to: ControlPlane

  @doc """
  Start an install flow through the auth subsystem.
  """
  @spec start_install(String.t(), String.t(), map()) ::
          {:ok, %{install: Install.t(), connection: Connection.t(), session_state: map()}}
          | {:error, term()}
  defdelegate start_install(connector_id, tenant_id, opts \\ %{}), to: Auth

  @doc """
  Complete an install and bind durable credential truth to the connection.
  """
  @spec complete_install(String.t(), map()) ::
          {:ok,
           %{install: Install.t(), connection: Connection.t(), credential_ref: CredentialRef.t()}}
          | {:error, term()}
  defdelegate complete_install(install_id, attrs), to: Auth

  @doc """
  Fetch a durable install session by id.
  """
  @spec fetch_install(String.t()) :: {:ok, Install.t()} | {:error, :unknown_install}
  defdelegate fetch_install(install_id), to: Auth

  @doc """
  List durable installs through the shared operator surface.
  """
  @spec installs(map()) :: [Install.t()]
  defdelegate installs(filters \\ %{}), to: Auth

  @doc """
  Fetch safe connection status through the host-facing auth boundary.
  """
  @spec connection_status(String.t()) :: {:ok, Connection.t()} | {:error, :unknown_connection}
  defdelegate connection_status(connection_id), to: Auth

  @doc """
  List durable connections through the shared operator surface.
  """
  @spec connections(map()) :: [Connection.t()]
  defdelegate connections(filters \\ %{}), to: Auth

  @doc """
  Issue a short-lived lease for runtime execution.
  """
  @spec request_lease(String.t(), map()) :: {:ok, CredentialLease.t()} | {:error, term()}
  defdelegate request_lease(connection_id, opts \\ %{}), to: Auth

  @doc """
  Rotate a connection's durable secret truth without changing its credential ref.
  """
  @spec rotate_connection(String.t(), map()) ::
          {:ok, %{connection: Connection.t(), credential_ref: CredentialRef.t()}}
          | {:error, term()}
  defdelegate rotate_connection(connection_id, attrs), to: Auth

  @doc """
  Revoke a connection and invalidate future lease use.
  """
  @spec revoke_connection(String.t(), map()) :: {:ok, Connection.t()} | {:error, term()}
  defdelegate revoke_connection(connection_id, attrs), to: Auth

  @doc """
  Invoke a capability through the control plane using a typed request.
  """
  @spec invoke(InvocationRequest.t()) ::
          {:ok, %{run: Run.t(), attempt: Jido.Integration.V2.Attempt.t(), output: map()}}
          | {:error, ControlPlane.invoke_preflight_error()}
          | {:error,
             %{
               reason: term(),
               run: Run.t(),
               attempt: Jido.Integration.V2.Attempt.t() | nil,
               policy_decision: Jido.Integration.V2.PolicyDecision.t() | nil
             }}
  defdelegate invoke(request), to: ControlPlane

  @doc """
  Invoke a capability through the control plane.

  Public callers bind auth with `:connection_id` when the capability requires
  a durable connection.
  """
  @spec invoke(String.t(), map(), keyword()) ::
          {:ok, %{run: Run.t(), attempt: Jido.Integration.V2.Attempt.t(), output: map()}}
          | {:error, ControlPlane.invoke_preflight_error()}
          | {:error,
             %{
               reason: term(),
               run: Run.t(),
               attempt: Jido.Integration.V2.Attempt.t() | nil,
               policy_decision: Jido.Integration.V2.PolicyDecision.t() | nil
             }}
  defdelegate invoke(capability_id, input, opts \\ []), to: ControlPlane

  @doc """
  Re-execute an accepted or failed run as a new attempt through the control
  plane.

  Completed, denied, and shed runs are terminal and are rejected without
  mutating durable run truth.
  """
  @spec execute_run(String.t(), pos_integer(), keyword()) ::
          {:ok, %{run: Run.t(), attempt: Jido.Integration.V2.Attempt.t(), output: map()}}
          | {:error,
             %{
               reason: term(),
               run: Run.t(),
               attempt: Jido.Integration.V2.Attempt.t() | nil,
               policy_decision: Jido.Integration.V2.PolicyDecision.t() | nil
             }}
          | {:error, :unknown_run | {:unknown_capability, String.t()}}
  defdelegate execute_run(run_id, attempt_number, opts \\ []), to: ControlPlane

  @doc """
  Fetch a previously recorded run.
  """
  @spec fetch_run(String.t()) :: {:ok, Run.t()} | :error
  defdelegate fetch_run(run_id), to: ControlPlane

  @doc """
  Fetch a previously recorded attempt.
  """
  @spec fetch_attempt(String.t()) :: {:ok, Attempt.t()} | :error
  defdelegate fetch_attempt(attempt_id), to: ControlPlane

  @doc """
  List canonical events for a run.
  """
  @spec events(String.t()) :: [Event.t()]
  defdelegate events(run_id), to: ControlPlane

  @doc """
  Record an artifact reference emitted by the control plane or runtime.
  """
  @spec record_artifact(ArtifactRef.t()) :: :ok | {:error, term()}
  defdelegate record_artifact(artifact_ref), to: ControlPlane

  @doc """
  Fetch a durable artifact reference by id.
  """
  @spec fetch_artifact(String.t()) :: {:ok, ArtifactRef.t()} | :error
  defdelegate fetch_artifact(artifact_id), to: ControlPlane

  @doc """
  List durable artifact references for a run.
  """
  @spec run_artifacts(String.t()) :: [ArtifactRef.t()]
  defdelegate run_artifacts(run_id), to: ControlPlane

  @doc """
  Upsert a target announcement into durable control-plane truth.
  """
  @spec announce_target(TargetDescriptor.t()) :: :ok | {:error, term()}
  defdelegate announce_target(target_descriptor), to: ControlPlane

  @doc """
  Fetch a durable target descriptor by id.
  """
  @spec fetch_target(String.t()) :: {:ok, TargetDescriptor.t()} | :error
  defdelegate fetch_target(target_id), to: ControlPlane

  @doc """
  List durable target descriptors through the shared operator surface.
  """
  @spec targets(map()) :: [TargetDescriptor.t()]
  defdelegate targets(filters \\ %{}), to: ControlPlane

  @doc """
  Return targets compatible with the requested capability/runtime/version posture.
  """
  @spec compatible_targets(map()) :: [%{target: TargetDescriptor.t(), negotiated_versions: map()}]
  defdelegate compatible_targets(requirements), to: ControlPlane

  @doc """
  Summarize connector catalog entries for operator-facing discovery.
  """
  @spec catalog_entries() :: [map()]
  defdelegate catalog_entries(), to: Operator

  @doc """
  Export the common projected consumer surface with generated identities and
  JSON Schema payloads for tools and docs consumers.
  """
  @spec projected_catalog_entries() :: [map()]
  defdelegate projected_catalog_entries(), to: Operator

  @doc """
  Derive authored-compatible target matches for a capability.
  """
  @spec compatible_targets_for(String.t(), map()) ::
          {:ok, [map()]} | {:error, :unknown_capability | :unknown_connector}
  defdelegate compatible_targets_for(capability_id, requirements \\ %{}), to: Operator

  @doc """
  Assemble a shared review packet from durable auth and control-plane truth.
  """
  @spec review_packet(String.t(), map()) ::
          {:ok, map()}
          | {:error, :unknown_run | :unknown_attempt | :unknown_capability | :unknown_connector}
  defdelegate review_packet(run_id, opts \\ %{}), to: Operator

  @doc """
  Reset in-memory state for tests and local exploration.
  """
  @spec reset!() :: :ok
  defdelegate reset!(), to: ControlPlane
end
