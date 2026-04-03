defmodule Jido.Integration.V2.AuthTest do
  use ExUnit.Case

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef

  setup do
    Auth.reset!()
    Auth.set_refresh_handler(nil)
    Auth.set_external_secret_resolver(nil)
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
               profile_id: "oauth_user",
               flow_kind: :manual_callback,
               state_token: "state-install-1",
               subject: "octocat",
               requested_scopes: ["repo"],
               metadata: %{redirect_uri: "/auth/github/callback"},
               now: started_at
             })

    assert install.state == :installing
    assert install.profile_id == "oauth_user"
    assert install.flow_kind == :manual_callback
    assert install.state_token == "state-install-1"
    assert install.callback_uri == "/auth/github/callback"
    assert connection.state == :installing
    assert connection.profile_id == "oauth_user"
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
               secret_source: :hosted_callback,
               source: :hosted_callback,
               expires_at: expires_at,
               now: started_at
             })

    assert completed_install.state == :completed
    assert connected_connection.state == :connected
    assert connected_connection.install_id == install.install_id
    assert connected_connection.credential_ref_id == credential_ref.id
    assert connected_connection.current_credential_id == credential_ref.current_credential_id
    assert connected_connection.subject == "octocat"
    assert connected_connection.granted_scopes == ["repo"]
    assert connected_connection.token_expires_at == expires_at
    assert connected_connection.profile_id == "oauth_user"
    assert connected_connection.secret_source == :hosted_callback
    assert credential_ref.subject == "octocat"
    assert credential_ref.scopes == ["repo"]
    assert credential_ref.connection_id == connection.connection_id
    assert credential_ref.profile_id == "oauth_user"
    assert credential_ref.current_credential_id == connected_connection.current_credential_id
    assert credential_ref.lease_fields == ["access_token"]
    assert credential_ref.metadata.connection_id == connection.connection_id
    assert credential_ref.metadata.install_id == install.install_id

    assert {:ok, binding} =
             Auth.resolve_connection_binding(connection.connection_id, %{now: started_at})

    assert binding.credential.id == connected_connection.current_credential_id
    assert binding.credential.credential_ref_id == credential_ref.id
    assert binding.credential.version == 1
    assert binding.credential.profile_id == "oauth_user"
    assert binding.credential.source == :hosted_callback

    install_id = install.install_id
    connection_id = connection.connection_id

    assert {:ok, %Install{install_id: ^install_id, state: :completed}} =
             Auth.fetch_install(install.install_id)

    assert {:ok, %Connection{connection_id: ^connection_id, state: :connected}} =
             Auth.connection_status(connection.connection_id)
  end

  test "resolves hosted callbacks with correlation, PKCE validation, and anti-replay" do
    started_at = ~U[2026-03-09 12:00:00Z]
    callback_at = ~U[2026-03-09 12:00:30Z]
    pkce_verifier = "github-pkce-verifier"

    assert {:ok,
            %{
              install: %Install{} = install,
              connection: %Connection{} = connection,
              session_state: session_state
            }} =
             Auth.start_install("github", "tenant-callback", %{
               actor_id: "user-callback",
               auth_type: :oauth2,
               flow_kind: :manual_callback,
               state_token: "state-callback-1",
               pkce_verifier_digest: ArtifactBuilder.digest(pkce_verifier),
               subject: "octocat",
               requested_scopes: ["repo"],
               callback_uri: "/auth/github/callback",
               now: started_at
             })

    assert install.callback_token == session_state.callback_token

    assert {:error, :invalid_callback_state} =
             Auth.resolve_install_callback(%{
               "callback_token" => install.callback_token,
               "state_token" => "wrong-state",
               "pkce_verifier" => pkce_verifier,
               "now" => callback_at
             })

    assert {:error, :invalid_pkce_verifier} =
             Auth.resolve_install_callback(%{
               "callback_token" => install.callback_token,
               "state_token" => install.state_token,
               "pkce_verifier" => pkce_verifier <> "-wrong",
               "now" => callback_at
             })

    assert {:ok,
            %{install: %Install{} = callback_install, connection: %Connection{} = callback_conn}} =
             Auth.resolve_install_callback(%{
               "callback_token" => install.callback_token,
               "state_token" => install.state_token,
               "pkce_verifier" => pkce_verifier,
               "callback_uri" => "/auth/github/callback?code=oauth-code",
               "callback_received_at" => callback_at,
               "now" => callback_at
             })

    assert callback_conn.connection_id == connection.connection_id
    assert callback_install.state == :awaiting_callback
    assert callback_install.callback_received_at == callback_at
    assert callback_install.callback_uri == "/auth/github/callback?code=oauth-code"

    install_id = install.install_id

    assert {:ok, %Install{install_id: ^install_id, state: :awaiting_callback}} =
             Auth.fetch_install(install.install_id)

    assert {:error, :callback_already_consumed} =
             Auth.resolve_install_callback(%{
               install_id: install.install_id,
               now: DateTime.add(callback_at, 1, :second)
             })
  end

  test "provider callback errors fail installs without requiring PKCE success-path material" do
    started_at = ~U[2026-03-09 12:10:00Z]
    callback_at = ~U[2026-03-09 12:10:20Z]

    assert {:ok, %{install: %Install{} = install, connection: %Connection{} = connection}} =
             Auth.start_install("github", "tenant-callback-error", %{
               actor_id: "user-callback-error",
               auth_type: :oauth2,
               flow_kind: :manual_callback,
               state_token: "state-callback-error",
               pkce_verifier_digest: ArtifactBuilder.digest("github-error-pkce"),
               subject: "octocat",
               requested_scopes: ["repo"],
               now: started_at
             })

    assert {:error,
            {:callback_error,
             %{error: "access_denied", description: "user_cancelled_browser_flow"}}} =
             Auth.resolve_install_callback(%{
               "callback_token" => install.callback_token,
               "state_token" => install.state_token,
               "error" => "access_denied",
               "error_description" => "user_cancelled_browser_flow",
               "now" => callback_at
             })

    assert {:ok, %Install{state: :failed} = failed_install} =
             Auth.fetch_install(install.install_id)

    assert failed_install.failure_reason =~ "access_denied"

    assert {:ok, %Connection{state: :disabled} = disabled_connection} =
             Auth.connection_status(connection.connection_id)

    assert disabled_connection.disabled_reason =~ "callback"
    assert {:error, :connection_disabled} = Auth.request_lease(connection.connection_id, %{})
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

    initial_credential_id = credential_ref.current_credential_id

    Auth.set_refresh_handler(fn %Connection{} = refreshed_connection, credential ->
      assert refreshed_connection.connection_id == connection.connection_id
      assert credential.id == initial_credential_id

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
    assert lease.credential_ref_id == credential_ref.id

    connection_id = connection.connection_id

    assert {:ok, %Connection{connection_id: ^connection_id} = refreshed_connection} =
             Auth.connection_status(connection.connection_id)

    assert refreshed_connection.state == :connected
    assert refreshed_connection.token_expires_at == refreshed_until
    assert refreshed_connection.last_refresh_at == ~U[2026-03-09 12:01:00Z]
    assert refreshed_connection.last_refresh_status == :ok
    assert refreshed_connection.current_credential_id != initial_credential_id
    assert lease.credential_id == refreshed_connection.current_credential_id

    assert {:ok, binding} =
             Auth.resolve_connection_binding(connection.connection_id, %{
               now: ~U[2026-03-09 12:01:00Z]
             })

    assert binding.credential.id == refreshed_connection.current_credential_id
    assert binding.credential.version == 2
    assert binding.credential.supersedes_credential_id == initial_credential_id
    assert binding.credential.credential_ref_id == credential_ref.id

    assert {:ok, resolved_credential} = Auth.resolve(binding.credential_ref, %{})
    assert resolved_credential.secret == %{}
    refute inspect(resolved_credential) =~ "gho_fresh_secret"
    refute inspect(resolved_credential) =~ "ghr_rotated_refresh_secret"
  end

  test "resolves a specific secret value through the auth boundary" do
    {_, _, credential_ref} =
      install_connection(%{
        connector_id: "github",
        tenant_id: "tenant-secret",
        actor_id: "user-secret",
        auth_type: :oauth2,
        subject: "secret-octocat",
        requested_scopes: ["repo"],
        granted_scopes: ["repo"],
        secret: %{
          access_token: "gho_secret_value",
          webhook_secret: "whsec_123"
        },
        expires_at: ~U[2026-03-09 13:00:00Z],
        now: ~U[2026-03-09 12:00:00Z]
      })

    assert {:ok, "whsec_123"} = Auth.resolve_secret(credential_ref, "webhook_secret")
    assert {:error, :unknown_secret} = Auth.resolve_secret(credential_ref, "missing_secret")
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
    assert rotated_ref.current_credential_id == rotated_connection.current_credential_id
    assert rotated_connection.current_credential_id != credential_ref.current_credential_id

    assert {:ok, %CredentialLease{payload: %{api_key: "new_market_secret"}} = rotated_lease} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["market:read"],
               now: DateTime.add(rotated_at, 1, :second)
             })

    assert rotated_lease.credential_id == rotated_connection.current_credential_id

    assert {:ok, binding} =
             Auth.resolve_connection_binding(connection.connection_id, %{
               now: ~U[2026-03-09 12:31:00Z]
             })

    assert binding.credential.id == rotated_connection.current_credential_id
    assert binding.credential.version == 2
    assert binding.credential.supersedes_credential_id == credential_ref.current_credential_id

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

  test "reinstalling against an existing connection keeps the credential ref stable and versions the durable credential" do
    {_, connection, credential_ref} =
      install_connection(%{
        connector_id: "notion",
        tenant_id: "tenant-reauth",
        actor_id: "user-reauth",
        auth_type: :oauth2,
        profile_id: "workspace_oauth",
        flow_kind: :manual_callback,
        subject: "workspace:acme",
        requested_scopes: ["notion.content.read"],
        granted_scopes: ["notion.content.read"],
        secret: %{access_token: "notion-initial", refresh_token: "notion-refresh"},
        expires_at: ~U[2026-03-09 13:00:00Z],
        now: ~U[2026-03-09 12:00:00Z]
      })

    assert {:ok, %{install: %Install{} = reinstall, connection: %Connection{} = installing}} =
             Auth.start_install("notion", "tenant-reauth", %{
               connection_id: connection.connection_id,
               actor_id: "user-reauth-2",
               auth_type: :oauth2,
               profile_id: "workspace_oauth",
               flow_kind: :manual_callback,
               subject: "workspace:acme",
               requested_scopes: ["notion.content.read", "notion.content.update"],
               now: ~U[2026-03-09 12:30:00Z]
             })

    assert reinstall.reauth_of_connection_id == connection.connection_id
    assert reinstall.profile_id == "workspace_oauth"
    assert installing.connection_id == connection.connection_id
    assert installing.credential_ref_id == credential_ref.id

    assert {:ok, %{connection: reauthed_connection, credential_ref: next_ref}} =
             Auth.complete_install(reinstall.install_id, %{
               subject: "workspace:acme",
               granted_scopes: ["notion.content.read", "notion.content.update"],
               secret: %{
                 access_token: "notion-rotated",
                 refresh_token: "notion-refresh-2"
               },
               source: :hosted_callback,
               secret_source: :hosted_callback,
               expires_at: ~U[2026-03-09 14:00:00Z],
               now: ~U[2026-03-09 12:31:00Z]
             })

    assert next_ref.id == credential_ref.id
    assert next_ref.current_credential_id != credential_ref.current_credential_id
    assert reauthed_connection.current_credential_id == next_ref.current_credential_id

    assert {:ok, binding} =
             Auth.resolve_connection_binding(connection.connection_id, %{
               now: ~U[2026-03-09 12:31:00Z]
             })

    assert binding.credential.id == next_ref.current_credential_id
    assert binding.credential.version == 2
    assert binding.credential.supersedes_credential_id == credential_ref.current_credential_id
  end

  test "canceling reauthorization restores the previous connection truth and lease path" do
    started_at = ~U[2026-03-09 12:00:00Z]

    {_, connection, credential_ref} =
      install_connection(%{
        connector_id: "notion",
        tenant_id: "tenant-reauth-cancel",
        actor_id: "user-reauth-cancel",
        auth_type: :oauth2,
        profile_id: "workspace_oauth",
        flow_kind: :manual_callback,
        subject: "workspace:acme",
        requested_scopes: ["notion.content.read"],
        granted_scopes: ["notion.content.read"],
        secret: %{access_token: "notion-old", refresh_token: "notion-refresh"},
        expires_at: ~U[2026-03-09 13:00:00Z],
        now: started_at
      })

    reauth_at = ~U[2026-03-09 12:30:00Z]

    assert {:ok,
            %{
              install: %Install{} = reauth_install,
              connection: %Connection{} = installing_connection
            }} =
             Auth.reauthorize_connection(connection.connection_id, %{
               actor_id: "user-reauth-cancel-2",
               profile_id: "workspace_admin",
               flow_kind: :manual_callback,
               requested_scopes: ["notion.content.read", "notion.content.update"],
               state_token: "state-reauth-cancel",
               now: reauth_at
             })

    assert reauth_install.reauth_of_connection_id == connection.connection_id
    assert reauth_install.metadata.install_origin == :reauth
    assert reauth_install.metadata.reauth_snapshot.profile_id == "workspace_oauth"
    assert installing_connection.state == :installing
    assert installing_connection.profile_id == "workspace_admin"

    assert installing_connection.requested_scopes == [
             "notion.content.read",
             "notion.content.update"
           ]

    assert installing_connection.current_credential_id == credential_ref.current_credential_id

    assert {:error, :connection_installing} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["notion.content.read"],
               now: reauth_at
             })

    cancel_at = ~U[2026-03-09 12:31:00Z]

    assert {:ok,
            %{
              install: %Install{} = cancelled_install,
              connection: %Connection{} = restored_connection
            }} =
             Auth.cancel_install(reauth_install.install_id, %{
               actor_id: "user-reauth-cancel-2",
               reason: "user_cancelled",
               now: cancel_at
             })

    assert cancelled_install.state == :cancelled
    assert cancelled_install.cancelled_at == cancel_at
    assert cancelled_install.failure_reason == "user_cancelled"
    assert restored_connection.state == :connected
    assert restored_connection.profile_id == "workspace_oauth"
    assert restored_connection.requested_scopes == ["notion.content.read"]
    assert restored_connection.current_credential_ref_id == credential_ref.id
    assert restored_connection.current_credential_id == credential_ref.current_credential_id

    assert {:ok, %CredentialLease{} = restored_lease} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["notion.content.read"],
               now: DateTime.add(cancel_at, 1, :second)
             })

    assert restored_lease.payload == %{access_token: "notion-old"}
    assert restored_lease.credential_id == credential_ref.current_credential_id
  end

  test "expiring a new install disables the provisional connection" do
    started_at = ~U[2026-03-09 13:00:00Z]
    expired_at = ~U[2026-03-09 13:10:00Z]

    assert {:ok, %{install: %Install{} = install, connection: %Connection{} = connection}} =
             Auth.start_install("github", "tenant-expire", %{
               actor_id: "user-expire",
               auth_type: :oauth2,
               flow_kind: :manual_callback,
               subject: "octocat",
               requested_scopes: ["repo"],
               now: started_at
             })

    assert {:ok,
            %{install: %Install{} = expired_install, connection: %Connection{} = disabled_conn}} =
             Auth.expire_install(install.install_id, %{
               actor_id: "system-expirer",
               reason: "install_ttl_elapsed",
               now: expired_at
             })

    assert expired_install.state == :expired
    assert expired_install.failure_reason == "install_ttl_elapsed"
    assert disabled_conn.state == :disabled
    assert disabled_conn.disabled_reason =~ "install_ttl_elapsed"

    assert {:error, :connection_disabled} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["repo"],
               now: expired_at
             })
  end

  test "external-secret lease issuance fails deterministically and degrades the connection when runtime material cannot be resolved" do
    started_at = ~U[2026-03-10 12:00:00Z]
    expires_at = ~U[2026-03-10 13:00:00Z]

    assert {:ok, %{install: install, connection: connection}} =
             Auth.start_install("linear", "tenant-ext", %{
               actor_id: "user-ext",
               auth_type: :oauth2,
               profile_id: "workspace_oauth",
               subject: "workspace:acme",
               requested_scopes: ["issues:read"],
               external_secret_ref: %{provider: :vault, ref: "vault://linear/workspace-acme"},
               secret_source: :external_ref,
               metadata: %{external_secret_failure_state: :degraded},
               now: started_at
             })

    assert {:ok, %{connection: %{connection_id: connection_id}}} =
             Auth.complete_install(install.install_id, %{
               subject: "workspace:acme",
               granted_scopes: ["issues:read"],
               secret: %{},
               lease_fields: ["access_token"],
               secret_source: :external_ref,
               source: :external_secret,
               expires_at: expires_at,
               now: started_at
             })

    assert connection_id == connection.connection_id

    assert {:error, :external_secret_unavailable} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["issues:read"],
               now: ~U[2026-03-10 12:01:00Z]
             })

    assert {:ok, %Connection{state: :degraded} = degraded_connection} =
             Auth.connection_status(connection.connection_id)

    assert degraded_connection.degraded_reason =~ "external_secret"
    assert degraded_connection.metadata.external_secret_resolution.status == :error
    assert degraded_connection.metadata.external_secret_resolution.stage == :lease

    assert degraded_connection.metadata.external_secret_resolution.requested_fields == [
             "access_token"
           ]
  end

  test "expired external-secret connections hydrate refresh material before invoking the refresh handler" do
    started_at = ~U[2026-03-10 12:00:00Z]
    expired_at = ~U[2026-03-10 12:00:00Z]
    refreshed_until = ~U[2026-03-10 14:00:00Z]

    assert {:ok, %{install: install, connection: connection}} =
             Auth.start_install("linear", "tenant-refresh", %{
               actor_id: "user-refresh",
               auth_type: :oauth2,
               profile_id: "workspace_oauth",
               subject: "workspace:refresh-acme",
               requested_scopes: ["issues:read"],
               external_secret_ref: %{provider: :vault, ref: "vault://linear/refresh-acme"},
               secret_source: :external_ref,
               now: started_at
             })

    assert {:ok, %{connection: %{connection_id: connection_id}}} =
             Auth.complete_install(install.install_id, %{
               subject: "workspace:refresh-acme",
               granted_scopes: ["issues:read"],
               secret: %{},
               lease_fields: ["access_token"],
               secret_source: :external_ref,
               source: :external_secret,
               expires_at: expired_at,
               now: started_at
             })

    assert connection_id == connection.connection_id

    Auth.set_external_secret_resolver(fn %Connection{} = resolving_connection, credential, opts ->
      send(
        self(),
        {:external_secret_resolved, resolving_connection.connection_id, opts, credential.id}
      )

      {:ok,
       %{
         refresh_token: "external-refresh-token"
       }}
    end)

    Auth.set_refresh_handler(fn %Connection{} = refreshed_connection, credential ->
      send(
        self(),
        {:refresh_handler_called, refreshed_connection.connection_id, credential.secret}
      )

      assert refreshed_connection.connection_id == connection.connection_id
      assert credential.secret == %{refresh_token: "external-refresh-token"}

      {:ok,
       %{
         secret: %{
           access_token: "fresh-external-access",
           refresh_token: "rotated-external-refresh"
         },
         expires_at: refreshed_until
       }}
    end)

    assert {:ok, %CredentialLease{} = lease} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["issues:read"],
               now: ~U[2026-03-10 12:01:00Z]
             })

    assert lease.payload == %{access_token: "fresh-external-access"}

    assert_received {:external_secret_resolved, ^connection_id, resolve_opts, credential_id}
    assert resolve_opts.stage == :refresh
    assert resolve_opts.requested_fields == ["refresh_token"]
    assert is_binary(credential_id)

    assert_received {:refresh_handler_called, ^connection_id,
                     %{refresh_token: "external-refresh-token"}}

    assert {:ok, %Connection{} = refreshed_connection} =
             Auth.connection_status(connection.connection_id)

    assert refreshed_connection.state == :connected
    assert refreshed_connection.last_refresh_status == :ok
    assert refreshed_connection.token_expires_at == refreshed_until
  end

  test "fetching an external-secret lease rehydrates payload keys from the external resolver" do
    started_at = ~U[2026-03-10 12:00:00Z]
    expires_at = ~U[2026-03-10 13:00:00Z]
    lease_now = ~U[2026-03-10 12:01:00Z]
    fetch_now = ~U[2026-03-10 12:01:10Z]

    assert {:ok, %{install: install, connection: connection}} =
             Auth.start_install("linear", "tenant-fetch", %{
               actor_id: "user-fetch",
               auth_type: :oauth2,
               profile_id: "workspace_oauth",
               subject: "workspace:fetch-acme",
               requested_scopes: ["issues:read"],
               external_secret_ref: %{provider: :vault, ref: "vault://linear/fetch-acme"},
               secret_source: :external_ref,
               now: started_at
             })

    assert {:ok, %{connection: %{connection_id: connection_id}}} =
             Auth.complete_install(install.install_id, %{
               subject: "workspace:fetch-acme",
               granted_scopes: ["issues:read"],
               secret: %{},
               lease_fields: ["access_token"],
               secret_source: :external_ref,
               source: :external_secret,
               expires_at: expires_at,
               now: started_at
             })

    assert connection_id == connection.connection_id

    Auth.set_external_secret_resolver(fn %Connection{} = resolving_connection,
                                         _credential,
                                         opts ->
      send(
        self(),
        {:external_secret_resolution_stage, resolving_connection.connection_id, opts.stage}
      )

      {:ok, %{access_token: "external-fetch-token"}}
    end)

    assert {:ok, %CredentialLease{} = lease} =
             Auth.request_lease(connection.connection_id, %{
               required_scopes: ["issues:read"],
               now: lease_now
             })

    assert lease.payload == %{access_token: "external-fetch-token"}

    assert {:ok, %CredentialLease{} = fetched_lease} =
             Auth.fetch_lease(lease.lease_id, %{now: fetch_now})

    assert fetched_lease.payload == %{access_token: "external-fetch-token"}

    assert_received {:external_secret_resolution_stage, ^connection_id, :lease}
    assert_received {:external_secret_resolution_stage, ^connection_id, :fetch_lease}
  end

  defp install_connection(attrs) do
    started_at = Map.fetch!(attrs, :now)

    start_opts = %{
      actor_id: Map.fetch!(attrs, :actor_id),
      auth_type: Map.fetch!(attrs, :auth_type),
      profile_id: Map.get(attrs, :profile_id),
      flow_kind: Map.get(attrs, :flow_kind),
      state_token: Map.get(attrs, :state_token),
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
               source: Map.get(attrs, :source),
               secret_source: Map.get(attrs, :secret_source),
               expires_at: Map.get(attrs, :expires_at),
               now: started_at
             })

    assert completed_install.state == :completed
    assert completed_connection.state == :connected

    {completed_install, completed_connection, credential_ref}
  end
end
