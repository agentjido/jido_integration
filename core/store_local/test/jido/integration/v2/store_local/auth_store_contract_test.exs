defmodule Jido.Integration.V2.StoreLocal.AuthStoreContractTest do
  use Jido.Integration.V2.StoreLocal.Case

  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.StoreLocal
  alias Jido.Integration.V2.StoreLocal.ConnectionStore
  alias Jido.Integration.V2.StoreLocal.CredentialStore
  alias Jido.Integration.V2.StoreLocal.InstallStore
  alias Jido.Integration.V2.StoreLocal.LeaseStore
  alias Jido.Integration.V2.StoreLocal.Server

  test "round-trips auth truth and upserts existing records" do
    credential = credential_fixture()
    connection = connection_fixture(%{connection_id: credential.connection_id})
    install = install_fixture(%{connection_id: connection.connection_id})
    lease = lease_record_fixture(credential, %{connection_id: connection.connection_id})

    assert :ok = CredentialStore.store_credential(credential)
    assert :ok = ConnectionStore.store_connection(connection)
    assert :ok = InstallStore.store_install(install)
    assert :ok = LeaseStore.store_lease(lease)

    assert {:ok, ^credential} = CredentialStore.fetch_credential(credential.id)
    assert {:ok, ^connection} = ConnectionStore.fetch_connection(connection.connection_id)
    assert {:ok, ^install} = InstallStore.fetch_install(install.install_id)
    assert {:ok, ^lease} = LeaseStore.fetch_lease(lease.lease_id)

    updated_credential = %{
      credential
      | secret: %{access_token: "rotated-token"},
        metadata: %{owner: "rotated"}
    }

    updated_connection = %{connection | state: :degraded, metadata: %{source: "rotated"}}
    updated_install = %{install | state: :completed, completed_at: install.expires_at}
    updated_lease = %{lease | revoked_at: DateTime.add(lease.issued_at, 120, :second)}

    assert :ok = CredentialStore.store_credential(updated_credential)
    assert :ok = ConnectionStore.store_connection(updated_connection)
    assert :ok = InstallStore.store_install(updated_install)
    assert :ok = LeaseStore.store_lease(updated_lease)

    assert {:ok, ^updated_credential} = CredentialStore.fetch_credential(credential.id)
    assert {:ok, ^updated_connection} = ConnectionStore.fetch_connection(connection.connection_id)
    assert {:ok, ^updated_install} = InstallStore.fetch_install(install.install_id)
    assert {:ok, ^updated_lease} = LeaseStore.fetch_lease(lease.lease_id)

    assert {:error, :unknown_credential} = CredentialStore.fetch_credential("credential-missing")
    assert {:error, :unknown_connection} = ConnectionStore.fetch_connection("connection-missing")
    assert {:error, :unknown_install} = InstallStore.fetch_install("install-missing")
    assert {:error, :unknown_lease} = LeaseStore.fetch_lease("lease-missing")

    refute File.read!(Server.storage_path()) =~ "rotated-token"
  end

  test "recovers auth truth after store restart" do
    credential = credential_fixture()
    connection = connection_fixture(%{connection_id: credential.connection_id})
    install = install_fixture(%{connection_id: connection.connection_id})
    lease = lease_record_fixture(credential, %{connection_id: connection.connection_id})

    assert :ok = CredentialStore.store_credential(credential)
    assert :ok = ConnectionStore.store_connection(connection)
    assert :ok = InstallStore.store_install(install)
    assert :ok = LeaseStore.store_lease(lease)

    assert :ok = TestSupport.restart_store!()

    assert {:ok, ^credential} = CredentialStore.fetch_credential(credential.id)
    assert {:ok, ^connection} = ConnectionStore.fetch_connection(connection.connection_id)
    assert {:ok, ^install} = InstallStore.fetch_install(install.install_id)
    assert {:ok, ^lease} = LeaseStore.fetch_lease(lease.lease_id)
  end

  test "supports explicit local durability configuration through the public auth API" do
    now = ~U[2026-03-12 12:00:00Z]

    assert Application.get_env(:jido_integration_v2_auth, :credential_store) == CredentialStore

    assert Application.get_env(:jido_integration_v2_control_plane, :run_store) ==
             Jido.Integration.V2.StoreLocal.RunStore

    assert {:ok,
            %{
              install: %Install{} = install,
              connection: %Connection{} = connection,
              session_state: %{callback_token: callback_token}
            }} =
             Auth.start_install("github", "tenant-1", %{
               actor_id: "user-1",
               auth_type: :oauth2,
               subject: "octocat",
               requested_scopes: ["repo"],
               metadata: %{redirect_uri: "/auth/github/callback"},
               now: now
             })

    assert is_binary(callback_token)

    assert {:ok,
            %{
              install: %Install{} = completed_install,
              connection: %Connection{} = completed_connection,
              credential_ref: %CredentialRef{} = credential_ref
            }} =
             Auth.complete_install(install.install_id, %{
               subject: "octocat",
               granted_scopes: ["repo"],
               secret: %{
                 access_token: "secret-token",
                 refresh_token: "refresh-secret"
               },
               expires_at: DateTime.add(now, 3600, :second),
               now: now
             })

    assert {:ok, %CredentialLease{} = lease} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["repo"],
               now: DateTime.add(now, 60, :second)
             })

    assert lease.payload == %{access_token: "secret-token"}
    assert completed_install.state == :completed
    assert completed_connection.state == :connected
    assert credential_ref.id == completed_connection.credential_ref_id

    assert :ok = TestSupport.restart_store!()

    install_id = install.install_id
    connection_id = connection.connection_id

    assert {:ok, %Install{install_id: ^install_id, state: :completed}} =
             Auth.fetch_install(install.install_id)

    assert {:ok, %Connection{connection_id: ^connection_id, state: :connected}} =
             Auth.connection_status(connection.connection_id)

    assert {:ok, %CredentialLease{} = recovered_lease} =
             Auth.fetch_lease(lease.lease_id, %{now: DateTime.add(now, 75, :second)})

    assert recovered_lease.payload == %{access_token: "secret-token"}
    assert StoreLocal.storage_path() == Server.storage_path()
  end
end
