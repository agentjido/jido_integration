defmodule Jido.Integration.V2.StorePostgres.ManagedAccountStoreTest do
  use Jido.Integration.V2.StorePostgres.DataCase

  alias Ecto.Adapters.SQL.Sandbox
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.MaterializationRequest
  alias Jido.Integration.V2.SecretMaterial
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.DurableRuntime
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.LeaseRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.ManagedAccountRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.ManagedCredentialVersionRecord
  alias Jido.Integration.V2.StorePostgres.TestSupport

  defmodule Materializer do
    @behaviour Jido.Integration.V2.CredentialMaterializer

    @impl true
    def materialize(lease, request) do
      SecretMaterial.new(%{
        materialization_ref: request.materialization_ref,
        provider_family: request.account.provider_family,
        account_ref: request.account.account_ref,
        generation: request.account.generation,
        payload: %{api_key: "postgres-transient-sentinel", lease_id: lease.lease_id}
      })
    end

    @impl true
    def revoke(_material, _opts), do: :ok
  end

  setup do
    Auth.reset!()

    Auth.configure_managed_accounts!(
      store: StorePostgres.managed_account_store(),
      materializers: %{"gemini" => Materializer}
    )

    :ok
  end

  test "managed account generation, fence, and revocation truth survive a repo restart" do
    now = ~U[2026-07-15 12:00:00Z]

    Sandbox.checkin(Repo)
    Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      TestSupport.reset_database!()
      Sandbox.mode(Repo, :auto)
    end)

    assert {:ok, %{account: account, account_ref: account_ref}} =
             Auth.register_managed_account(registration(now))

    assert account.generation == 1
    assert account.fence == 0

    account_row = Repo.get!(ManagedAccountRecord, account.account_ref)

    version_one =
      Repo.get_by!(ManagedCredentialVersionRecord,
        account_ref: account.account_ref,
        generation: 1
      )

    assert account_row.secret_provider_ref == "vault://nshkr/kv-v2"
    assert version_one.secret_binding_ref == "vault-secret://gemini/account-a/v1"
    refute inspect(account_row) =~ "postgres-sentinel-secret"
    refute inspect(version_one) =~ "postgres-sentinel-secret"

    assert {:error, {:secret_material_forbidden, [:api_key]}} =
             registration(now)
             |> Map.put(:api_key, "postgres-sentinel-secret")
             |> Auth.register_managed_account()

    assert {:ok, %{account: rotated, account_ref: rotated_ref}} =
             Auth.rotate_managed_account(account_ref, %{
               credential_handle_ref: "credential-handle://gemini/account-a/v2",
               secret_binding_ref: "vault-secret://gemini/account-a/v2",
               fence: 1,
               now: DateTime.add(now, 10, :second)
             })

    assert rotated.generation == 2
    assert rotated.fence == 1

    assert :ok = restart_repo!(:auto)
    assert {:ok, ^rotated} = Auth.fetch_managed_account(rotated_ref)

    persisted_version_one =
      Repo.get_by!(ManagedCredentialVersionRecord,
        account_ref: account.account_ref,
        generation: 1
      )

    persisted_version_two =
      Repo.get_by!(ManagedCredentialVersionRecord,
        account_ref: account.account_ref,
        generation: 2
      )

    assert DateTime.compare(
             persisted_version_one.superseded_at,
             DateTime.add(now, 10, :second)
           ) == :eq

    assert persisted_version_two.supersedes_generation == 1

    assert {:ok, revoked} =
             Auth.revoke_managed_account(rotated_ref, %{
               revocation_ref: "revocation://gemini/account-a/1",
               now: DateTime.add(now, 20, :second)
             })

    assert revoked.state == :revoked
    assert {:error, :managed_account_revoked} = Auth.request_managed_lease(rotated_ref, %{})
  end

  test "durable runtime exposes one explicit production child and a live preflight" do
    child_spec =
      DurableRuntime.child_spec(
        repo_options: [],
        persistence_profile: :integration_postgres,
        credential_materializers: %{"gemini" => Materializer}
      )

    assert child_spec.type == :supervisor

    assert child_spec.start ==
             {DurableRuntime, :start_link,
              [
                [
                  repo_options: [],
                  persistence_profile: :integration_postgres,
                  credential_materializers: %{"gemini" => Materializer}
                ]
              ]}

    assert :ok =
             DurableRuntime.preflight(
               repo_options: [],
               persistence_profile: :integration_postgres,
               credential_materializers: %{"gemini" => Materializer}
             )

    assert :ok =
             DurableRuntime.preflight(
               repo_mode: :external,
               repo_options: [],
               persistence_profile: :integration_postgres,
               credential_materializers: %{"gemini" => Materializer}
             )

    assert :ok = DurableRuntime.post_start_health()

    assert_raise ArgumentError, ~r/missing durable runtime options/, fn ->
      DurableRuntime.child_spec(repo_options: [])
    end
  end

  test "managed lease redemption and materialization truth survive a repo restart without secret material" do
    now = ~U[2026-07-15 13:00:00Z]

    Sandbox.checkin(Repo)
    Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      TestSupport.reset_database!()
      Sandbox.mode(Repo, :auto)
    end)

    assert {:ok, %{account: account, account_ref: account_ref}} =
             Auth.register_managed_account(registration(now))

    context = governed_context(account, now)
    assert {:ok, lease} = Auth.request_managed_lease(account_ref, context)
    assert lease.payload == %{}

    request =
      MaterializationRequest.new!(%{
        materialization_ref: "materialization://gemini/postgres/1",
        lease_id: lease.lease_id,
        account: account_ref,
        effect_ref: context.effect_ref,
        operation_ref: context.operation_ref,
        authority_ref: context.authority_ref,
        endpoint_ref: account.endpoint_ref,
        target_ref: context.target_ref,
        issued_at: DateTime.add(now, 1, :second),
        expires_at: DateTime.add(now, 30, :second)
      })

    assert {:ok, %{status: :used, account_ref: account_account_ref}} =
             Auth.with_materialized_credential(
               lease,
               request,
               redemption_context(context, now),
               fn material ->
                 assert material.payload.api_key == "postgres-transient-sentinel"
                 %{status: :used, account_ref: material.account_ref}
               end
             )

    assert account_account_ref == account.account_ref

    lease_row = Repo.get!(LeaseRecord, lease.lease_id)
    assert lease_row.redemption_count == 1
    assert lease_row.last_materialization_ref == request.materialization_ref
    refute inspect(lease_row) =~ "postgres-transient-sentinel"

    assert :ok = restart_repo!(:auto)

    assert {:ok, fetched_lease} =
             Auth.fetch_lease(lease.lease_id, %{
               tenant_id: account.tenant_id,
               now: DateTime.add(now, 3, :second)
             })

    assert fetched_lease.payload == %{}
    assert fetched_lease.metadata.redemption_count == 1
    assert fetched_lease.metadata.last_materialization_ref == request.materialization_ref
    refute inspect(fetched_lease) =~ "postgres-transient-sentinel"
  end

  defp registration(now) do
    %{
      provider_family: "gemini",
      account_ref: "provider-account://tenant-1/gemini/account-a",
      tenant_id: "tenant-1",
      connector_id: "gemini",
      endpoint_ref: "endpoint://gemini/generate-content",
      quota_scope_ref: "quota://gemini/account-a",
      credential_handle_ref: "credential-handle://gemini/account-a/v1",
      secret_provider_ref: "vault://nshkr/kv-v2",
      secret_binding_ref: "vault-secret://gemini/account-a/v1",
      subject: "nshkr-runtime",
      actor_id: "operator-1",
      scopes: ["model:invoke"],
      lease_fields: ["api_key"],
      now: now
    }
  end

  defp governed_context(account, now) do
    %{
      tenant_id: account.tenant_id,
      actor_id: "runtime-1",
      required_scopes: ["model:invoke"],
      ttl_seconds: 60,
      now: now,
      provider_family: account.provider_family,
      provider_account_ref: account.account_ref,
      connector_instance_ref: "connector-instance://gemini/primary",
      credential_handle_ref: account.credential_handle_ref,
      operation_class: "inference",
      execution_context_ref: "execution-context://run/1",
      target_ref: "target://gemini/local",
      attach_grant_ref: "attach-grant://gemini/1",
      operation_policy_ref: "operation-policy://gemini/generate",
      policy_revision_ref: "policy-revision://gemini/1",
      target_grant_revision: "target-grant-revision://gemini/1",
      rotation_epoch: account.generation,
      fence_token: "#{account.account_ref}:fence:#{account.fence}",
      authority_ref: "citadel://grant/gemini/1",
      authority_decision_ref: "citadel://decision/gemini/1",
      authority_scope: ["model:invoke"],
      installation_revision: "installation://nshkr/1",
      effect_ref: "effect://gemini/run-1/turn-1",
      operation_ref: "operation://gemini/generate-content/1",
      endpoint_ref: account.endpoint_ref,
      max_calls: 1,
      max_tokens: 4096,
      allowed_models: ["gemini-2.5-flash"],
      network_policy: :provider_only
    }
  end

  defp redemption_context(context, now) do
    %{
      tenant_id: context.tenant_id,
      provider_family: context.provider_family,
      connector_instance_ref: context.connector_instance_ref,
      provider_account_ref: context.provider_account_ref,
      credential_handle_ref: context.credential_handle_ref,
      operation_class: context.operation_class,
      target_ref: context.target_ref,
      attach_grant_ref: context.attach_grant_ref,
      operation_policy_ref: context.operation_policy_ref,
      current_policy_revision_ref: context.policy_revision_ref,
      current_rotation_epoch: context.rotation_epoch,
      current_target_grant_revision: context.target_grant_revision,
      fence_token: context.fence_token,
      current_installation_revision: context.installation_revision,
      requested_authority_scope: context.authority_scope,
      requested_model: "gemini-2.5-flash",
      requested_tokens: 512,
      network_target: :provider,
      now: DateTime.add(now, 2, :second)
    }
  end
end
