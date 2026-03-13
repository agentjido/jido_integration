defmodule Jido.Integration.V2.AuthTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef

  setup do
    Auth.reset!()
    Auth.set_refresh_handler(nil)
    :ok
  end

  test "host apps can start and complete installs into durable connections and credential refs" do
    started_at = ~U[2026-03-09 12:00:00Z]
    expires_at = ~U[2026-03-09 13:00:00Z]

    assert {:ok,
            %{
              install: %Install{} = install,
              connection: %Connection{} = connection,
              session_state: session_state
            }} =
             Auth.start_install("github", "tenant-1", %{
               actor_id: "user-1",
               auth_type: :oauth2,
               subject: "octocat",
               requested_scopes: ["repo"],
               metadata: %{redirect_uri: "/auth/github/callback"},
               now: started_at
             })

    assert install.state == :installing
    assert connection.state == :installing
    assert install.connection_id == connection.connection_id
    assert session_state.install_id == install.install_id
    assert is_binary(session_state.callback_token)

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
                 access_token: "gho_install_secret",
                 refresh_token: "ghr_install_secret"
               },
               expires_at: expires_at,
               now: started_at
             })

    assert completed_install.state == :completed
    assert connected_connection.state == :connected
    assert connected_connection.install_id == install.install_id
    assert connected_connection.credential_ref_id == credential_ref.id
    assert connected_connection.subject == "octocat"
    assert connected_connection.granted_scopes == ["repo"]
    assert connected_connection.token_expires_at == expires_at
    assert credential_ref.subject == "octocat"
    assert credential_ref.scopes == ["repo"]
    assert credential_ref.metadata.connection_id == connection.connection_id
    assert credential_ref.metadata.install_id == install.install_id

    install_id = install.install_id
    connection_id = connection.connection_id

    assert {:ok, %Install{install_id: ^install_id, state: :completed}} =
             Auth.fetch_install(install.install_id)

    assert {:ok, %Connection{connection_id: ^connection_id, state: :connected}} =
             Auth.connection_status(connection.connection_id)
  end

  test "issues minimal leases, rejects scope and subject mismatches, and expires them without cleanup" do
    {install, connection, credential_ref} =
      install_connection(%{
        connector_id: "github",
        tenant_id: "tenant-1",
        actor_id: "user-1",
        auth_type: :oauth2,
        subject: "octocat",
        requested_scopes: ["repo", "issues:write"],
        granted_scopes: ["repo", "issues:write"],
        secret: %{
          access_token: "gho_runtime_secret",
          refresh_token: "ghr_runtime_secret",
          client_secret: "client_secret_should_not_leak"
        },
        expires_at: ~U[2026-03-09 13:00:00Z],
        now: ~U[2026-03-09 12:00:00Z]
      })

    assert {:ok, %CredentialLease{} = lease} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["repo"],
               ttl_seconds: 30,
               now: ~U[2026-03-09 12:01:00Z],
               actor_id: "runtime-1"
             })

    assert lease.credential_ref_id == credential_ref.id
    assert lease.subject == "octocat"
    assert lease.scopes == ["repo"]
    assert lease.payload == %{access_token: "gho_runtime_secret"}
    refute Map.has_key?(lease.payload, :refresh_token)
    refute Map.has_key?(lease.payload, :client_secret)

    lease_id = lease.lease_id

    assert {:ok, %CredentialLease{lease_id: ^lease_id} = fetched_lease} =
             Auth.fetch_lease(lease.lease_id, %{now: ~U[2026-03-09 12:01:15Z]})

    assert fetched_lease.payload == %{access_token: "gho_runtime_secret"}

    assert {:error, :expired_lease} =
             Auth.fetch_lease(lease.lease_id, %{now: ~U[2026-03-09 12:01:31Z]})

    assert {:error, {:missing_connection_scopes, ["admin:repo_hook"]}} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["admin:repo_hook"],
               now: ~U[2026-03-09 12:01:00Z]
             })

    mismatched_ref = %CredentialRef{credential_ref | subject: "someone-else"}

    assert {:error, :credential_subject_mismatch} =
             Auth.issue_lease(mismatched_ref, %{
               required_scopes: ["repo"],
               now: ~U[2026-03-09 12:01:00Z]
             })

    install_id = install.install_id
    assert {:ok, %Install{install_id: ^install_id}} = Auth.fetch_install(install.install_id)
  end

  test "refreshes expired credentials before issuing a lease and keeps raw secret truth behind auth" do
    expired_at = ~U[2026-03-09 12:00:00Z]
    refreshed_until = ~U[2026-03-09 14:00:00Z]

    {_, connection, credential_ref} =
      install_connection(%{
        connector_id: "github",
        tenant_id: "tenant-2",
        actor_id: "user-2",
        auth_type: :oauth2,
        subject: "refresh-octocat",
        requested_scopes: ["repo"],
        granted_scopes: ["repo"],
        secret: %{
          access_token: "gho_expired_secret",
          refresh_token: "ghr_refresh_secret"
        },
        expires_at: expired_at,
        now: ~U[2026-03-09 11:59:00Z]
      })

    Auth.set_refresh_handler(fn %Connection{} = refreshed_connection, credential ->
      assert refreshed_connection.connection_id == connection.connection_id
      assert credential.id == credential_ref.id

      {:ok,
       %{
         secret: %{
           access_token: "gho_fresh_secret",
           refresh_token: "ghr_rotated_refresh_secret"
         },
         expires_at: refreshed_until
       }}
    end)

    assert {:ok, %CredentialLease{} = lease} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["repo"],
               now: ~U[2026-03-09 12:01:00Z]
             })

    assert lease.payload == %{access_token: "gho_fresh_secret"}

    connection_id = connection.connection_id

    assert {:ok, %Connection{connection_id: ^connection_id} = refreshed_connection} =
             Auth.connection_status(connection.connection_id)

    assert refreshed_connection.state == :connected
    assert refreshed_connection.token_expires_at == refreshed_until

    assert {:ok, resolved_credential} = Auth.resolve(credential_ref, %{})
    assert resolved_credential.secret == %{}
    refute inspect(resolved_credential) =~ "gho_fresh_secret"
    refute inspect(resolved_credential) =~ "ghr_rotated_refresh_secret"
  end

  test "rotates and revokes connections through the host boundary" do
    {_, connection, credential_ref} =
      install_connection(%{
        connector_id: "market_data",
        tenant_id: "tenant-3",
        actor_id: "user-3",
        auth_type: :api_key,
        subject: "market-reader",
        requested_scopes: ["market:read"],
        granted_scopes: ["market:read"],
        secret: %{api_key: "old_market_secret"},
        expires_at: nil,
        now: Contracts.now()
      })

    assert {:ok, %CredentialLease{payload: %{api_key: "old_market_secret"}}} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["market:read"],
               now: Contracts.now()
             })

    rotated_at = ~U[2026-03-09 15:00:00Z]

    assert {:ok,
            %{
              connection: %Connection{} = rotated_connection,
              credential_ref: %CredentialRef{} = rotated_ref
            }} =
             Auth.rotate_connection(connection.connection_id, %{
               actor_id: "user-4",
               granted_scopes: ["market:read"],
               secret: %{api_key: "new_market_secret"},
               now: rotated_at
             })

    assert rotated_connection.state == :connected
    assert rotated_connection.last_rotated_at == rotated_at
    assert rotated_ref.id == credential_ref.id

    assert {:ok, %CredentialLease{payload: %{api_key: "new_market_secret"}}} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["market:read"],
               now: DateTime.add(rotated_at, 1, :second)
             })

    revoked_at = ~U[2026-03-09 16:00:00Z]

    assert {:ok, %Connection{} = revoked_connection} =
             Auth.revoke_connection(connection.connection_id, %{
               actor_id: "user-5",
               reason: "manual_revoke",
               now: revoked_at
             })

    assert revoked_connection.state == :revoked
    assert revoked_connection.revoked_at == revoked_at
    assert revoked_connection.revocation_reason == "manual_revoke"

    assert {:error, :connection_revoked} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["market:read"],
               now: DateTime.add(revoked_at, 1, :second)
             })
  end

  defp install_connection(attrs) do
    started_at = Map.fetch!(attrs, :now)

    start_opts = %{
      actor_id: Map.fetch!(attrs, :actor_id),
      auth_type: Map.fetch!(attrs, :auth_type),
      subject: Map.fetch!(attrs, :subject),
      requested_scopes: Map.fetch!(attrs, :requested_scopes),
      metadata: Map.get(attrs, :metadata, %{}),
      now: started_at
    }

    assert {:ok, %{install: %Install{} = install, connection: %Connection{}}} =
             Auth.start_install(
               Map.fetch!(attrs, :connector_id),
               Map.fetch!(attrs, :tenant_id),
               start_opts
             )

    assert {:ok,
            %{
              install: %Install{} = completed_install,
              connection: %Connection{} = completed_connection,
              credential_ref: %CredentialRef{} = credential_ref
            }} =
             Auth.complete_install(install.install_id, %{
               subject: Map.fetch!(attrs, :subject),
               granted_scopes: Map.fetch!(attrs, :granted_scopes),
               secret: Map.fetch!(attrs, :secret),
               expires_at: Map.get(attrs, :expires_at),
               now: started_at
             })

    assert completed_install.state == :completed
    assert completed_connection.state == :connected

    {completed_install, completed_connection, credential_ref}
  end
end
