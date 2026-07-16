defmodule Jido.Integration.V2.AuthManagedAccountTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.ManagedAccount
  alias Jido.Integration.V2.MaterializationRequest
  alias Jido.Integration.V2.SecretMaterial

  defmodule Store do
    @behaviour Jido.Integration.V2.Auth.ManagedAccountStore

    use Agent

    def start_link(_opts),
      do: Agent.start_link(fn -> %{accounts: %{}, versions: %{}} end, name: __MODULE__)

    @impl true
    def transact(fun), do: fun.()

    @impl true
    def register(account, version) do
      Agent.get_and_update(__MODULE__, fn state ->
        if Map.has_key?(state.accounts, account.account_ref) do
          {{:error, :account_exists}, state}
        else
          {:ok,
           state
           |> put_in([:accounts, account.account_ref], account)
           |> put_in([:versions, {account.account_ref, version.generation}], version)}
        end
      end)
    end

    @impl true
    def fetch(account_ref) do
      Agent.get(__MODULE__, fn state ->
        case Map.get(state.accounts, account_ref) do
          nil -> {:error, :unknown_managed_account}
          account -> {:ok, account}
        end
      end)
    end

    @impl true
    def lock(account_ref), do: fetch(account_ref)

    @impl true
    def fetch_by_connection(connection_id) do
      Agent.get(__MODULE__, fn state ->
        case Enum.find(Map.values(state.accounts), &(&1.connection_id == connection_id)) do
          nil -> {:error, :unknown_managed_account}
          account -> {:ok, account}
        end
      end)
    end

    @impl true
    def fetch_version(account_ref, generation) do
      Agent.get(__MODULE__, fn state ->
        case Map.get(state.versions, {account_ref, generation}) do
          nil -> {:error, :unknown_credential_generation}
          version -> {:ok, version}
        end
      end)
    end

    @impl true
    def rotate(account_ref, expected_generation, fence, version, now) do
      Agent.get_and_update(__MODULE__, fn state ->
        case Map.get(state.accounts, account_ref) do
          nil ->
            {{:error, :unknown_managed_account}, state}

          %ManagedAccount{generation: generation} when generation != expected_generation ->
            {{:error, :stale_managed_account_generation}, state}

          %ManagedAccount{} = account ->
            rotated = %ManagedAccount{
              account
              | generation: version.generation,
                fence: fence,
                credential_handle_ref: version.credential_handle_ref,
                secret_provider_ref: version.secret_provider_ref,
                secret_binding_ref: version.secret_binding_ref,
                updated_at: now
            }

            {{:ok, rotated},
             state
             |> put_in([:accounts, account_ref], rotated)
             |> put_in([:versions, {account_ref, version.generation}], version)}
        end
      end)
    end

    @impl true
    def revoke(account_ref, expected_generation, expected_fence, revocation_ref, now) do
      Agent.get_and_update(__MODULE__, fn state ->
        case Map.get(state.accounts, account_ref) do
          nil ->
            {{:error, :unknown_managed_account}, state}

          %ManagedAccount{generation: generation, fence: fence}
          when generation != expected_generation or fence != expected_fence ->
            {{:error, :stale_managed_account_ref}, state}

          %ManagedAccount{} = account ->
            revoked = %ManagedAccount{
              account
              | state: :revoked,
                revoked_at: now,
                revocation_ref: revocation_ref,
                updated_at: now
            }

            {{:ok, revoked}, put_in(state, [:accounts, account_ref], revoked)}
        end
      end)
    end
  end

  defmodule Materializer do
    @behaviour Jido.Integration.V2.CredentialMaterializer

    @impl true
    def materialize(lease, request) do
      SecretMaterial.new(%{
        materialization_ref: request.materialization_ref,
        provider_family: request.account.provider_family,
        account_ref: request.account.account_ref,
        generation: request.account.generation,
        payload: %{api_key: "managed-sentinel-secret", lease_id: lease.lease_id}
      })
    end

    @impl true
    def revoke(_material, _opts), do: :ok
  end

  setup do
    start_supervised!(Store)
    Auth.reset!()
    Auth.configure_managed_accounts!(store: Store, materializers: %{"gemini" => Materializer})
    :ok
  end

  test "managed account generations stay durable-safe and materialize only in the bounded task" do
    now = ~U[2026-07-15 12:00:00Z]

    assert {:ok, %{account: account, account_ref: account_ref}} =
             Auth.register_managed_account(registration(now))

    assert account.generation == 1
    assert account.fence == 0
    refute inspect(account) =~ "managed-sentinel-secret"

    context = governed_context(account, now)

    assert {:error, :managed_account_required} =
             Auth.request_lease(account.connection_id, context)

    assert {:error, {:secret_material_forbidden, [:api_key]}} =
             Auth.request_managed_lease(
               account_ref,
               Map.put(context, :api_key, "managed-option-sentinel")
             )

    assert {:ok, lease} = Auth.request_managed_lease(account_ref, context)
    assert lease.payload == %{}
    assert lease.lease_fields == ["api_key"]

    request =
      MaterializationRequest.new!(%{
        materialization_ref: "materialization://gemini/1",
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

    parent = self()

    assert {:error, {:secret_material_forbidden, [:api_key]}} =
             Auth.with_materialized_credential(
               lease,
               request,
               redemption_context(context, now)
               |> Map.put(:api_key, "managed-redemption-option-sentinel"),
               fn _material -> :ok end
             )

    assert {:ok, %{status: :ok}} =
             Auth.with_materialized_credential(
               lease,
               request,
               redemption_context(context, now),
               fn material ->
                 send(parent, {:materialized_in, self(), material.payload.api_key})
                 %{status: :ok, account_ref: material.account_ref}
               end
             )

    assert_receive {:materialized_in, materialization_pid, "managed-sentinel-secret"}
    refute materialization_pid == self()

    assert {:ok, fetched_lease} =
             Auth.fetch_lease(lease.lease_id, %{tenant_id: account.tenant_id, now: now})

    assert fetched_lease.metadata.redemption_count == 1
    assert fetched_lease.metadata.last_materialization_ref == request.materialization_ref
    refute inspect(fetched_lease) =~ "managed-sentinel-secret"

    assert {:error, :secret_material_leak} =
             Auth.with_materialized_credential(
               lease,
               %{request | materialization_ref: "materialization://gemini/2"},
               redemption_context(context, now),
               fn material -> %{result: material.payload.api_key} end
             )

    assert {:error, :max_calls_exceeded} =
             Auth.with_materialized_credential(
               lease,
               %{request | materialization_ref: "materialization://gemini/3"},
               redemption_context(context, now),
               fn _material -> :ok end
             )

    assert {:ok, %{status: :revoked}} =
             Auth.revoke_lease(lease.lease_id, %{
               revocation_ref: "revocation://lease/gemini/1",
               now: DateTime.add(now, 3, :second)
             })

    assert {:error, :revoked_lease} =
             Auth.with_materialized_credential(
               lease,
               %{request | materialization_ref: "materialization://gemini/4"},
               redemption_context(context, now),
               fn _material -> :ok end
             )
  end

  test "cross-account, stale generation, and revoked account paths fail closed" do
    now = ~U[2026-07-15 13:00:00Z]

    assert {:ok, %{account: account, account_ref: account_ref}} =
             Auth.register_managed_account(registration(now))

    context = governed_context(account, now)

    assert {:error, {:managed_account_identity_mismatch, :tenant_id}} =
             Auth.request_managed_lease(account_ref, %{context | tenant_id: "tenant-other"})

    assert {:ok, %{account_ref: rotated_ref}} =
             Auth.rotate_managed_account(account_ref, %{
               secret_binding_ref: "vault-secret://gemini/account-a/v2",
               credential_handle_ref: "credential-handle://gemini/account-a/v2",
               fence: 1,
               now: DateTime.add(now, 10, :second)
             })

    assert rotated_ref.generation == 2

    assert {:error, :stale_managed_account_ref} =
             Auth.request_managed_lease(account_ref, context)

    assert {:error, {:secret_material_forbidden, [:api_key]}} =
             Auth.revoke_managed_account(rotated_ref, %{
               revocation_ref: "revocation://gemini/account-a/rejected",
               api_key: "managed-revocation-option-sentinel",
               now: DateTime.add(now, 15, :second)
             })

    assert {:ok, revoked} =
             Auth.revoke_managed_account(rotated_ref, %{
               revocation_ref: "revocation://gemini/account-a/1",
               now: DateTime.add(now, 20, :second)
             })

    assert revoked.state == :revoked

    assert {:error, :managed_account_revoked} =
             Auth.request_managed_lease(rotated_ref, governed_context(revoked, now))
  end

  test "materialization rejects cross-account, expired, future, and lease-outliving requests" do
    now = ~U[2026-07-15 14:00:00Z]

    assert {:ok, %{account: account_a, account_ref: account_a_ref}} =
             Auth.register_managed_account(registration(now))

    account_b_attrs =
      registration(now)
      |> Map.merge(%{
        account_ref: "provider-account://tenant-1/gemini/account-b",
        quota_scope_ref: "quota://gemini/account-b",
        credential_handle_ref: "credential-handle://gemini/account-b/v1",
        secret_binding_ref: "vault-secret://gemini/account-b/v1",
        subject: "nshkr-runtime-b"
      })

    assert {:ok, %{account_ref: account_b_ref}} =
             Auth.register_managed_account(account_b_attrs)

    context = governed_context(account_a, now)
    assert {:ok, lease} = Auth.request_managed_lease(account_a_ref, context)

    request =
      MaterializationRequest.new!(%{
        materialization_ref: "materialization://gemini/bounds/1",
        lease_id: lease.lease_id,
        account: account_a_ref,
        effect_ref: context.effect_ref,
        operation_ref: context.operation_ref,
        authority_ref: context.authority_ref,
        endpoint_ref: account_a.endpoint_ref,
        target_ref: context.target_ref,
        issued_at: DateTime.add(now, 1, :second),
        expires_at: DateTime.add(now, 20, :second)
      })

    assert {:error, :materialization_connection_mismatch} =
             Auth.with_materialized_credential(
               lease,
               %{request | account: account_b_ref},
               redemption_context(context, now),
               fn _material -> :ok end
             )

    assert {:error, :expired_materialization_request} =
             Auth.with_materialized_credential(
               lease,
               %{request | expires_at: DateTime.add(now, 2, :second)},
               redemption_context(context, DateTime.add(now, 3, :second)),
               fn _material -> :ok end
             )

    assert {:error, :materialization_not_yet_valid} =
             Auth.with_materialized_credential(
               lease,
               %{request | issued_at: DateTime.add(now, 5, :second)},
               redemption_context(context, now),
               fn _material -> :ok end
             )

    assert {:error, :materialization_outlives_lease} =
             Auth.with_materialized_credential(
               lease,
               %{request | expires_at: DateTime.add(lease.expires_at, 1, :second)},
               redemption_context(context, now),
               fn _material -> :ok end
             )

    assert {:ok, revoked} =
             Auth.revoke_managed_account(account_a_ref, %{
               revocation_ref: "revocation://gemini/account-a/materialization",
               now: DateTime.add(now, 4, :second)
             })

    assert revoked.state == :revoked

    assert {:error, :managed_account_revoked} =
             Auth.with_materialized_credential(
               lease,
               request,
               redemption_context(context, now),
               fn _material -> :ok end
             )
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
      max_calls: 2,
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
