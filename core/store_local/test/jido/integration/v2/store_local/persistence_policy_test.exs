defmodule Jido.Integration.V2.StoreLocal.PersistencePolicyTest do
  use Jido.Integration.V2.StoreLocal.Case

  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.StoreLocal
  alias Jido.Integration.V2.StoreLocal.CredentialStore
  alias Jido.Integration.V2.StoreLocal.RunStore

  test "configures local restart safe stores through explicit persistence policy" do
    assert {:ok, capability} = StoreLocal.store_capability()
    assert capability.tier == :local_restart_safe
    assert capability.restart_safe?
    assert capability.durable?

    assert :ok = StoreLocal.configure_defaults!(persistence_profile: :local_restart_safe)

    assert Auth.Stores.credential_store() == CredentialStore
    assert ControlPlane.Stores.run_store() == RunStore
  end

  test "configures local stores when persistence owner applications are not already started", %{
    storage_dir: storage_dir
  } do
    :ok = stop_application(:jido_integration_v2_store_local)
    :ok = stop_application(:jido_integration_v2_control_plane)
    :ok = stop_application(:jido_integration_v2_auth)

    assert :ok = StoreLocal.configure_defaults!(storage_dir: storage_dir)

    assert Process.whereis(Jido.Integration.V2.Auth.Persistence.Owner)
    assert Process.whereis(Jido.Integration.V2.ControlPlane.Persistence.Owner)
    assert Auth.Stores.credential_store() == CredentialStore
    assert ControlPlane.Stores.run_store() == RunStore
  end

  defp stop_application(app) when is_atom(app) do
    case Application.stop(app) do
      :ok -> :ok
      {:error, {:not_started, ^app}} -> :ok
      {:error, {:not_started, _dependency}} -> :ok
      {:error, reason} -> raise "unable to stop #{inspect(app)}: #{inspect(reason)}"
    end
  end
end
