defmodule Jido.Integration.V2.AuthLeaseRedemptionTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.Auth.LeaseRedemption
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef

  setup do
    Auth.reset!()
    Auth.set_refresh_handler(nil)
    Auth.set_external_secret_resolver(nil)
    :ok
  end

  test "authorizes a governed lease with redacted evidence only" do
    {_install, connection, _credential_ref} = install_codex_connection()

    assert {:ok, %CredentialLease{} = lease} =
             request_codex_lease(connection, %{
               max_calls: 3,
               max_tokens: 10_000,
               allowed_models: ["gpt-5.4"],
               network_policy: :provider_only
             })

    assert {:ok, evidence} =
             LeaseRedemption.authorize(lease, %{
               tenant_id: "tenant-1",
               connector_instance_ref: "connector-instance://tenant-1/codex/a",
               provider_account_ref: "provider-account://codex/redacted",
               requested_model: "gpt-5.4",
               requested_tokens: 100,
               network_target: :provider,
               redemption_count: 0,
               current_installation_revision: "install-rev-1",
               requested_authority_scope: ["codex:run"],
               now: ~U[2026-03-09 12:01:00Z]
             })

    assert evidence.redacted
    assert evidence.connector_instance_ref == "connector-instance://tenant-1/codex/a"
    refute inspect(evidence) =~ "phase4a-runtime-token"
    refute inspect(lease.metadata) =~ "phase4a-runtime-token"
  end

  test "rejects wrong connector, provider account, and tenant before materialization" do
    {_install, connection, _credential_ref} = install_codex_connection()
    assert {:ok, lease} = request_codex_lease(connection)

    assert {:error, :connector_mismatch} =
             LeaseRedemption.authorize(
               lease,
               base_redemption_context(%{
                 connector_instance_ref: "connector-instance://tenant-1/codex/b"
               })
             )

    assert {:error, :provider_account_mismatch} =
             LeaseRedemption.authorize(
               lease,
               base_redemption_context(%{
                 provider_account_ref: "provider-account://codex/other"
               })
             )

    assert {:error, :tenant_mismatch} =
             LeaseRedemption.authorize(lease, base_redemption_context(%{tenant_id: "tenant-2"}))
  end

  test "enforces max calls, model, token, and network constraints" do
    {_install, connection, _credential_ref} = install_codex_connection()

    assert {:ok, lease} =
             request_codex_lease(connection, %{
               max_calls: 3,
               max_tokens: 200,
               allowed_models: ["gpt-5.4"],
               network_policy: :provider_only
             })

    assert {:error, :max_calls_exceeded} =
             LeaseRedemption.authorize(lease, base_redemption_context(%{redemption_count: 3}))

    assert {:error, :model_not_allowed} =
             LeaseRedemption.authorize(
               lease,
               base_redemption_context(%{requested_model: "gpt-5.5"})
             )

    assert {:error, :max_tokens_exceeded} =
             LeaseRedemption.authorize(lease, base_redemption_context(%{requested_tokens: 201}))

    assert {:error, :network_policy_mismatch} =
             LeaseRedemption.authorize(
               lease,
               base_redemption_context(%{network_target: :external})
             )
  end

  test "rejects stale revisions and authority widening" do
    {_install, connection, _credential_ref} = install_codex_connection()
    assert {:ok, lease} = request_codex_lease(connection)

    assert {:error, :stale_installation_revision} =
             LeaseRedemption.authorize(
               lease,
               base_redemption_context(%{current_installation_revision: "install-rev-2"})
             )

    assert {:error, :authority_scope_widening} =
             LeaseRedemption.authorize(
               lease,
               base_redemption_context(%{requested_authority_scope: ["codex:run", "linear:read"]})
             )
  end

  test "standalone contexts and secret material returns cannot satisfy governed redemption" do
    {_install, connection, _credential_ref} = install_codex_connection()

    assert {:ok, standalone_lease} =
             request_codex_lease(connection, %{
               execution_context_scope: :standalone,
               authority_scope: ["codex:run"]
             })

    assert {:error, :standalone_context_cannot_govern} =
             LeaseRedemption.authorize(
               standalone_lease,
               base_redemption_context(%{requested_authority_mode: :governed})
             )

    assert {:error, :secret_material_return_forbidden} =
             LeaseRedemption.authorize(
               standalone_lease,
               base_redemption_context(%{return_secret_material?: true})
             )
  end

  test "revoked connections reject already issued lease fetches" do
    {_install, connection, _credential_ref} = install_codex_connection()
    assert {:ok, lease} = request_codex_lease(connection)

    assert {:ok, %Connection{state: :revoked}} =
             Auth.revoke_connection(connection.connection_id, %{
               actor_id: "user-1",
               reason: "phase4a_revocation",
               now: ~U[2026-03-09 12:02:00Z]
             })

    assert {:error, :connection_revoked} =
             Auth.fetch_lease(lease.lease_id, %{
               tenant_id: "tenant-1",
               now: ~U[2026-03-09 12:02:01Z]
             })
  end

  defp install_codex_connection do
    install_connection(%{
      connector_id: "codex_cli",
      tenant_id: "tenant-1",
      actor_id: "user-1",
      auth_type: :oauth2,
      subject: "codex-user",
      requested_scopes: ["codex:run"],
      granted_scopes: ["codex:run"],
      secret: %{access_token: "phase4a-runtime-token", refresh_token: "phase4a-refresh-token"},
      expires_at: ~U[2026-03-09 13:00:00Z],
      now: ~U[2026-03-09 12:00:00Z]
    })
  end

  defp request_codex_lease(%Connection{} = connection, attrs \\ %{}) do
    context =
      Map.merge(
        %{
          tenant_id: "tenant-1",
          actor_id: "runtime-1",
          required_scopes: ["codex:run"],
          ttl_seconds: 300,
          now: ~U[2026-03-09 12:01:00Z],
          connector_instance_ref: "connector-instance://tenant-1/codex/a",
          provider_account_ref: "provider-account://codex/redacted",
          execution_context_ref: "execution-context://tenant-1/codex/run-1",
          execution_context_scope: :governed,
          authority_ref: "citadel://authority/decision-1",
          authority_decision_ref: "citadel://authority/decision-1",
          authority_scope: ["codex:run"],
          installation_revision: "install-rev-1",
          max_calls: 3,
          max_tokens: :unlimited,
          allowed_models: :any,
          network_policy: :provider_only
        },
        attrs
      )

    Auth.request_lease(connection.connection_id, context)
  end

  defp base_redemption_context(attrs) do
    Map.merge(
      %{
        tenant_id: "tenant-1",
        connector_instance_ref: "connector-instance://tenant-1/codex/a",
        provider_account_ref: "provider-account://codex/redacted",
        requested_model: "gpt-5.4",
        requested_tokens: 100,
        network_target: :provider,
        redemption_count: 0,
        current_installation_revision: "install-rev-1",
        requested_authority_scope: ["codex:run"],
        now: ~U[2026-03-09 12:01:00Z]
      },
      attrs
    )
  end

  defp install_connection(attrs) do
    started_at = Map.fetch!(attrs, :now)

    start_opts = %{
      actor_id: Map.fetch!(attrs, :actor_id),
      auth_type: Map.fetch!(attrs, :auth_type),
      subject: Map.fetch!(attrs, :subject),
      requested_scopes: Map.fetch!(attrs, :requested_scopes),
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
