defmodule Jido.Integration.V2.StorePostgres.AuthStoreTest do
  use Jido.Integration.V2.StorePostgres.DataCase

  alias Ecto.Adapters.SQL.Sandbox
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.StorePostgres.ConnectionStore
  alias Jido.Integration.V2.StorePostgres.InstallStore
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.ConnectionRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.CredentialRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.InstallRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.LeaseRecord
  alias Jido.Integration.V2.StorePostgres.TestSupport

  setup do
    Auth.reset!()
    Auth.set_refresh_handler(nil)
    :ok
  end

  test "encrypts credential truth, keeps host-facing models safe, and persists minimal leases across repo restart" do
    now = ~U[2026-03-09 12:00:00Z]
    expires_at = ~U[2026-03-09 13:00:00Z]

    Sandbox.checkin(Repo)
    Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      Auth.set_refresh_handler(nil)
      TestSupport.reset_database!()
      Sandbox.mode(Repo, :auto)
    end)

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
              connection: %Connection{} = connected_connection,
              credential_ref: %CredentialRef{} = credential_ref
            }} =
             Auth.complete_install(install.install_id, %{
               subject: "octocat",
               granted_scopes: ["repo"],
               secret: %{
                 access_token: "secret-token",
                 refresh_token: "refresh-secret",
                 client_secret: "client-secret"
               },
               expires_at: expires_at,
               now: now
             })

    assert {:ok, lease} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["repo"],
               ttl_seconds: 45,
               now: DateTime.add(now, 60, :second)
             })

    refute inspect(completed_install) =~ "secret-token"
    refute inspect(connected_connection) =~ "secret-token"

    credential_row = Repo.get!(CredentialRecord, credential_ref.id)
    refute inspect(credential_row.secret_envelope) =~ "secret-token"
    refute inspect(credential_row.secret_envelope) =~ "refresh-secret"
    refute inspect(credential_row.secret_envelope) =~ "client-secret"
    assert credential_row.secret_envelope["ciphertext"]
    assert credential_row.secret_envelope["tag"]
    assert credential_row.secret_envelope["iv"]
    assert credential_row.credential_ref_id == credential_ref.id
    assert credential_row.profile_id == "default"
    assert credential_row.version == 1

    install_row = Repo.get!(InstallRecord, install.install_id)
    connection_row = Repo.get!(ConnectionRecord, connection.connection_id)
    lease_row = Repo.get!(LeaseRecord, lease.lease_id)

    assert install_row.state == "completed"
    assert install_row.profile_id == "default"
    assert install_row.flow_kind == "manual_callback"
    assert install_row.callback_uri == "/auth/github/callback"
    assert connection_row.state == "connected"
    assert connection_row.profile_id == "default"
    assert connection_row.credential_ref_id == credential_ref.id
    assert connection_row.current_credential_ref_id == credential_ref.id
    assert connection_row.current_credential_id == credential_ref.id
    assert connection_row.management_mode == "manual"
    assert connection_row.secret_source == "hosted_callback"
    assert lease_row.credential_id == credential_ref.id
    assert lease_row.profile_id == "default"
    assert lease_row.payload_keys == ["access_token"]
    refute inspect(lease_row) =~ "secret-token"
    refute inspect(lease_row) =~ "refresh-secret"

    assert :ok = restart_repo!(:auto)

    install_id = install.install_id
    connection_id = connection.connection_id

    assert {:ok, %Install{install_id: ^install_id, state: :completed}} =
             Auth.fetch_install(install.install_id)

    assert {:ok, %Connection{connection_id: ^connection_id, state: :connected}} =
             Auth.connection_status(connection.connection_id)

    assert {:ok, fetched_lease} =
             Auth.fetch_lease(lease.lease_id, %{now: DateTime.add(now, 75, :second)})

    assert fetched_lease.payload == %{access_token: "secret-token"}
  end

  test "refresh updates encrypted durable credential truth without persisting refresh material into the lease table" do
    now = ~U[2026-03-09 12:00:00Z]

    assert {:ok, %{install: %Install{} = install, connection: %Connection{} = connection}} =
             Auth.start_install("github", "tenant-2", %{
               actor_id: "user-2",
               auth_type: :oauth2,
               subject: "refresh-user",
               requested_scopes: ["repo"],
               now: now
             })

    assert {:ok, %{credential_ref: %CredentialRef{} = credential_ref}} =
             Auth.complete_install(install.install_id, %{
               subject: "refresh-user",
               granted_scopes: ["repo"],
               secret: %{
                 access_token: "expired-access-token",
                 refresh_token: "durable-refresh-token"
               },
               expires_at: now,
               now: now
             })

    Auth.set_refresh_handler(fn %Connection{connection_id: refreshed_id}, credential ->
      assert refreshed_id == connection.connection_id
      assert credential.id == credential_ref.id

      {:ok,
       %{
         secret: %{
           access_token: "fresh-access-token",
           refresh_token: "rotated-refresh-token"
         },
         expires_at: ~U[2026-03-09 15:00:00Z]
       }}
    end)

    assert {:ok, lease} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["repo"],
               now: DateTime.add(now, 1, :second)
             })

    assert lease.payload == %{access_token: "fresh-access-token"}

    assert {:ok, refreshed_connection} = Auth.connection_status(connection.connection_id)
    assert refreshed_connection.current_credential_ref_id == credential_ref.id
    refute refreshed_connection.current_credential_id == credential_ref.id

    credential_row = Repo.get!(CredentialRecord, refreshed_connection.current_credential_id)
    lease_row = Repo.get!(LeaseRecord, lease.lease_id)

    assert credential_row.credential_ref_id == credential_ref.id
    assert credential_row.version == 2
    assert credential_row.supersedes_credential_id == credential_ref.id
    refute inspect(credential_row.secret_envelope) =~ "fresh-access-token"
    refute inspect(credential_row.secret_envelope) =~ "rotated-refresh-token"
    assert lease_row.credential_id == refreshed_connection.current_credential_id
    assert lease_row.credential_ref_id == credential_ref.id
    refute inspect(lease_row) =~ "fresh-access-token"
    refute inspect(lease_row) =~ "rotated-refresh-token"
    assert lease_row.payload_keys == ["access_token"]
  end

  test "lists durable installs and connections with stable filtering" do
    now = ~U[2026-03-09 12:30:00Z]

    assert {:ok, %{install: first_install, connection: first_connection}} =
             Auth.start_install("github", "tenant-ops", %{
               actor_id: "user-ops",
               auth_type: :oauth2,
               subject: "octocat",
               requested_scopes: ["repo"],
               now: now
             })

    assert {:ok, %{install: second_install, connection: second_connection}} =
             Auth.start_install("codex_cli", "tenant-ops", %{
               actor_id: "user-ops",
               auth_type: :oauth2,
               subject: "desk-analyst",
               requested_scopes: ["session:execute"],
               now: DateTime.add(now, 1, :second)
             })

    assert Enum.map(
             ConnectionStore.list_connections(%{tenant_id: "tenant-ops"}),
             & &1.connection_id
           ) ==
             [first_connection.connection_id, second_connection.connection_id]

    assert Enum.map(InstallStore.list_installs(%{connector_id: "github"}), & &1.install_id) == [
             first_install.install_id
           ]

    assert Enum.map(InstallStore.list_installs(%{tenant_id: "tenant-ops"}), & &1.install_id) == [
             first_install.install_id,
             second_install.install_id
           ]
  end
end
