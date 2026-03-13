defmodule Jido.Integration.V2 do
  @moduledoc """
  Public facade package for the greenfield `jido_integration_v2` platform.

  The tooling workspace lives at the repository root. Runtime entrypoints live
  here and delegate to the child packages that implement the control plane,
  auth boundary, and shared contracts.
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
  Fetch safe connection status through the host-facing auth boundary.
  """
  @spec connection_status(String.t()) :: {:ok, Connection.t()} | {:error, :unknown_connection}
  defdelegate connection_status(connection_id), to: Auth

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
  Invoke a capability through the control plane.
  """
  @spec invoke(String.t(), map(), keyword()) ::
          {:ok, %{run: Run.t(), attempt: Jido.Integration.V2.Attempt.t(), output: map()}}
          | {:error,
             %{
               reason: term(),
               run: Run.t(),
               attempt: Jido.Integration.V2.Attempt.t() | nil,
               policy_decision: Jido.Integration.V2.PolicyDecision.t() | nil
             }}
  defdelegate invoke(capability_id, input, opts \\ []), to: ControlPlane

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
  Return targets compatible with the requested capability/runtime/version posture.
  """
  @spec compatible_targets(map()) :: [%{target: TargetDescriptor.t(), negotiated_versions: map()}]
  defdelegate compatible_targets(requirements), to: ControlPlane

  @doc """
  Reset in-memory state for tests and local exploration.
  """
  @spec reset!() :: :ok
  defdelegate reset!(), to: ControlPlane
end
