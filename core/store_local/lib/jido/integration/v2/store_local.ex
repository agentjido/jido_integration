defmodule Jido.Integration.V2.StoreLocal do
  @moduledoc """
  Local durable adapter package for auth and control-plane store behaviours.
  """

  alias Jido.Integration.V2.StoreLocal.ArtifactStore
  alias Jido.Integration.V2.StoreLocal.AttemptStore
  alias Jido.Integration.V2.StoreLocal.ConnectionStore
  alias Jido.Integration.V2.StoreLocal.CredentialStore
  alias Jido.Integration.V2.StoreLocal.EventStore
  alias Jido.Integration.V2.StoreLocal.IngressStore
  alias Jido.Integration.V2.StoreLocal.InstallStore
  alias Jido.Integration.V2.StoreLocal.LeaseStore
  alias Jido.Integration.V2.StoreLocal.RunStore
  alias Jido.Integration.V2.StoreLocal.TargetStore

  @default_storage_dir Path.join(System.tmp_dir!(), "jido_integration_v2_store_local")
  @state_file "state.bin"

  @spec configure_defaults!(keyword()) :: :ok
  def configure_defaults!(opts \\ []) do
    if storage_dir = opts[:storage_dir] do
      Application.put_env(
        :jido_integration_v2_store_local,
        :storage_dir,
        storage_dir |> Path.expand() |> String.trim_trailing("/")
      )
    end

    Application.put_env(:jido_integration_v2_auth, :credential_store, CredentialStore)
    Application.put_env(:jido_integration_v2_auth, :lease_store, LeaseStore)
    Application.put_env(:jido_integration_v2_auth, :connection_store, ConnectionStore)
    Application.put_env(:jido_integration_v2_auth, :install_store, InstallStore)

    Application.put_env(:jido_integration_v2_control_plane, :run_store, RunStore)
    Application.put_env(:jido_integration_v2_control_plane, :attempt_store, AttemptStore)
    Application.put_env(:jido_integration_v2_control_plane, :event_store, EventStore)
    Application.put_env(:jido_integration_v2_control_plane, :artifact_store, ArtifactStore)
    Application.put_env(:jido_integration_v2_control_plane, :target_store, TargetStore)
    Application.put_env(:jido_integration_v2_control_plane, :ingress_store, IngressStore)
    :ok
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
    Jido.Integration.V2.StoreLocal.Server.reset!()
  end
end
