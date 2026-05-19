defmodule Jido.Integration.V2.StoreLocal do
  @moduledoc """
  Local durable adapter package for auth and control-plane store behaviours.
  """

  alias GroundPlane.PersistencePolicy
  alias Jido.Integration.V2.Auth.Persistence, as: AuthPersistence
  alias Jido.Integration.V2.ControlPlane.Persistence, as: ControlPlanePersistence
  alias Jido.Integration.V2.StoreLocal.ArtifactStore
  alias Jido.Integration.V2.StoreLocal.AttemptStore
  alias Jido.Integration.V2.StoreLocal.ConnectionStore
  alias Jido.Integration.V2.StoreLocal.CredentialStore
  alias Jido.Integration.V2.StoreLocal.EventStore
  alias Jido.Integration.V2.StoreLocal.IngressStore
  alias Jido.Integration.V2.StoreLocal.InstallStore
  alias Jido.Integration.V2.StoreLocal.LeaseStore
  alias Jido.Integration.V2.StoreLocal.ProfileRegistryStore
  alias Jido.Integration.V2.StoreLocal.RunStore
  alias Jido.Integration.V2.StoreLocal.Server
  alias Jido.Integration.V2.StoreLocal.TargetStore

  @default_storage_dir Path.join(System.tmp_dir!(), "jido_integration_v2_store_local")
  @state_file "state.bin"

  @spec configure_defaults!(keyword()) :: :ok
  def configure_defaults!(opts \\ []) do
    profile = Keyword.get(opts, :persistence_profile, :local_restart_safe)
    {:ok, capability} = store_capability()

    if storage_dir = opts[:storage_dir] do
      Application.put_env(
        :jido_integration_v2_store_local,
        :storage_dir,
        storage_dir |> Path.expand() |> String.trim_trailing("/")
      )
    end

    auth_store_modules = auth_store_modules()
    control_plane_store_modules = control_plane_store_modules()

    Application.put_env(
      :jido_integration_v2_auth,
      :credential_store,
      auth_store_modules.credential_store
    )

    Application.put_env(:jido_integration_v2_auth, :lease_store, auth_store_modules.lease_store)

    Application.put_env(
      :jido_integration_v2_auth,
      :connection_store,
      auth_store_modules.connection_store
    )

    Application.put_env(
      :jido_integration_v2_auth,
      :install_store,
      auth_store_modules.install_store
    )

    Application.put_env(
      :jido_integration_v2_control_plane,
      :run_store,
      control_plane_store_modules.run_store
    )

    Application.put_env(
      :jido_integration_v2_control_plane,
      :attempt_store,
      control_plane_store_modules.attempt_store
    )

    Application.put_env(
      :jido_integration_v2_control_plane,
      :event_store,
      control_plane_store_modules.event_store
    )

    Application.put_env(
      :jido_integration_v2_control_plane,
      :artifact_store,
      control_plane_store_modules.artifact_store
    )

    Application.put_env(
      :jido_integration_v2_control_plane,
      :target_store,
      control_plane_store_modules.target_store
    )

    Application.put_env(
      :jido_integration_v2_control_plane,
      :ingress_store,
      control_plane_store_modules.ingress_store
    )

    Application.put_env(
      :jido_integration_v2_control_plane,
      :profile_registry_store,
      control_plane_store_modules.profile_registry_store
    )

    Application.put_env(
      :jido_integration_v2_brain_ingress,
      :submission_ledger,
      Jido.Integration.V2.StoreLocal.SubmissionLedger
    )

    :ok = ensure_started!(:jido_integration_v2_auth)
    :ok = ensure_started!(:jido_integration_v2_control_plane)

    :ok =
      AuthPersistence.configure!(
        profile: profile,
        capabilities: [capability],
        store_modules: auth_store_modules
      )

    :ok =
      ControlPlanePersistence.configure!(
        profile: profile,
        capabilities: [capability],
        store_modules: control_plane_store_modules
      )

    :ok
  end

  defp ensure_started!(app) when is_atom(app) do
    case Application.ensure_all_started(app) do
      {:ok, _apps} ->
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "unable to start #{inspect(app)} before configuring StoreLocal persistence: #{inspect(reason)}"
    end
  end

  @spec store_capability() :: {:ok, PersistencePolicy.StoreCapability.t()} | {:error, term()}
  def store_capability do
    PersistencePolicy.StoreCapability.new(
      store_ref: :jido_integration_store_local,
      tier: :local_restart_safe,
      data_classes: [:auth_truth, :control_plane_truth, :submission_ledger],
      adapter: :jido_integration_store_local,
      restart_safe?: true,
      partitions: [
        %PersistencePolicy.Partition{
          data_class: :jido_integration,
          retention_class: :restart_safe_local
        }
      ]
    )
  end

  @spec storage_dir() :: String.t()
  def storage_dir do
    :jido_integration_v2_store_local
    |> Application.get_env(:storage_dir, @default_storage_dir)
    |> Path.expand()
  end

  @spec storage_path() :: String.t()
  def storage_path do
    Path.join(storage_dir(), @state_file)
  end

  @spec reset!() :: :ok
  def reset! do
    Server.reset!()
  end

  defp auth_store_modules do
    %{
      credential_store: CredentialStore,
      lease_store: LeaseStore,
      connection_store: ConnectionStore,
      install_store: InstallStore
    }
  end

  defp control_plane_store_modules do
    %{
      run_store: RunStore,
      attempt_store: AttemptStore,
      event_store: EventStore,
      artifact_store: ArtifactStore,
      claim_check_store: Jido.Integration.V2.ControlPlane.RunLedger,
      target_store: TargetStore,
      ingress_store: IngressStore,
      profile_registry_store: ProfileRegistryStore
    }
  end
end
