defmodule Jido.Integration.Secrets.ProviderTest do
  use ExUnit.Case

  alias Jido.Integration.Secrets.Broker
  alias Jido.Integration.Secrets.EnvProvider
  alias Jido.Integration.Secrets.EphemeralProvider
  alias Jido.Integration.Secrets.KeyringProvider
  alias Jido.Integration.Secrets.ManagedCredentialMaterializer
  alias Jido.Integration.Secrets.VaultKVProvider
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.ManagedAccount
  alias Jido.Integration.V2.MaterializationRequest

  defmodule ManagedStore do
    @behaviour Jido.Integration.V2.Auth.ManagedAccountStore

    use Agent

    def start_link(_opts),
      do: Agent.start_link(fn -> %{accounts: %{}, versions: %{}} end, name: __MODULE__)

    @impl true
    def transact(fun), do: fun.()

    @impl true
    def register(account, version) do
      Agent.update(__MODULE__, fn state ->
        state
        |> put_in([:accounts, account.account_ref], account)
        |> put_in([:versions, {account.account_ref, version.generation}], version)
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
    def rotate(_account_ref, _expected_generation, _fence, _version, _now),
      do: {:error, :unsupported_in_test_store}

    @impl true
    def revoke(_account_ref, _generation, _fence, _revocation_ref, _now),
      do: {:error, :unsupported_in_test_store}
  end

  defmodule VaultHTTP do
    def request(:get, url, headers, _opts) do
      send(self(), {:vault_request, url, headers})

      body =
        Jason.encode!(%{
          "data" => %{
            "data" => %{"api_key" => "vault-sentinel", "ignored" => "value"},
            "metadata" => %{"version" => 7, "created_time" => "2026-07-15T00:00:00Z"}
          }
        })

      {:ok, %{status: 200, body: body}}
    end
  end

  setup do
    prior_config =
      Application.get_env(:jido_integration_secrets_provider, :managed_providers, :missing)

    on_exit(fn ->
      case prior_config do
        :missing ->
          Application.delete_env(:jido_integration_secrets_provider, :managed_providers)

        config ->
          Application.put_env(:jido_integration_secrets_provider, :managed_providers, config)
      end
    end)

    :ok
  end

  test "env provider materializes a scoped handle and keeps receipts redacted" do
    assert {:ok, result} =
             Broker.with_materialized(
               EnvProvider,
               "lease://linear/live/1",
               %{env_var: "LINEAR_API_KEY", secret_key: :api_key},
               fn material, public_ref ->
                 assert material == %{api_key: "lin_api_secret"}
                 refute inspect(public_ref) =~ "lin_api_secret"
                 {:ok, Broker.public_receipt(public_ref, :used)}
               end,
               env: %{"LINEAR_API_KEY" => "lin_api_secret"}
             )

    assert result.secret_material_redacted? == true
    assert result.provider_ref == "env://LINEAR_API_KEY"
    refute inspect(result) =~ "lin_api_secret"
  end

  test "ephemeral provider keeps stdin material inside the broker callback" do
    materializer = fn -> %{api_key: "stdin-secret"} end

    assert {:ok, :called} =
             Broker.with_materialized(
               EphemeralProvider,
               "lease://linear/stdin/1",
               %{provider_ref: "ephemeral://stdin", secret_key: :api_key},
               fn material, public_ref ->
                 assert material.api_key == "stdin-secret"
                 refute inspect(public_ref) =~ "stdin-secret"
                 {:ok, :called}
               end,
               secret_materializer: materializer
             )
  end

  test "keyring provider fails closed for dev keys in production" do
    keyring = %{entries: %{"dev-local-1" => %{api_key: "secret"}}}

    assert {:error, {:dev_local_key_rejected, "dev-local-1"}} =
             KeyringProvider.materialize(
               "lease://prod/1",
               %{key_id: "dev-local-1"},
               keyring: keyring,
               runtime_env: :prod
             )
  end

  test "keyring provider emits rotation, revocation, and audit refs without material" do
    keyring = %{
      entries: %{"kms-prod-1" => %{api_key: "prod-secret"}},
      rotation_posture_by_key_id: %{"kms-prod-1" => :kms_managed}
    }

    assert {:ok, result} =
             Broker.with_materialized(
               KeyringProvider,
               "lease://prod/2",
               %{key_id: "kms-prod-1"},
               fn material, public_ref ->
                 assert material.api_key == "prod-secret"
                 {:ok, Broker.public_receipt(public_ref, :used)}
               end,
               keyring: keyring,
               runtime_env: :prod
             )

    assert result.provider_ref == "keyring://kms-prod-1"
    refute inspect(result) =~ "prod-secret"

    assert {:ok, %{status: :rotation_requested, next_key_id: "kms-prod-2"}} =
             KeyringProvider.rotate("binding://linear/main", next_key_id: "kms-prod-2")

    assert {:ok, %{status: :revoked, recovery_owner: :secrets_operator}} =
             KeyringProvider.revoke("lease://prod/2", key_id: "kms-prod-1")
  end

  test "vault provider uses an explicit transient token and returns only safe receipts" do
    token_loader = fn -> "vault-token-sentinel" end

    assert {:ok, receipt} =
             Broker.with_materialized(
               VaultKVProvider,
               "lease://gemini/1",
               %{mount: "nshkr", path: "gemini/account-a", fields: ["api_key"]},
               fn material, public_ref ->
                 assert material == %{"api_key" => "vault-sentinel"}
                 refute inspect(public_ref) =~ "vault-sentinel"
                 {:ok, Broker.public_receipt(public_ref, :used)}
               end,
               address: "https://vault.internal",
               token_loader: token_loader,
               http_client: VaultHTTP
             )

    assert receipt.secret_material_redacted?
    refute inspect(receipt) =~ "vault-sentinel"

    assert_received {:vault_request, url, headers}
    assert url == "https://vault.internal/v1/nshkr/data/gemini/account-a"
    assert {"x-vault-token", "vault-token-sentinel"} in headers
  end

  test "vault managed scope rejects malformed durable refs without raising" do
    assert {:error, :invalid_vault_binding} =
             VaultKVProvider.managed_scope(
               %{
                 secret_provider_ref: nil,
                 secret_binding_ref: "vault-secret://gemini/account/v1"
               },
               %{},
               %{}
             )

    assert {:error, {:invalid_vault_binding, :secret_binding_ref}} =
             VaultKVProvider.managed_scope(
               %{
                 secret_provider_ref: "vault://nshkr/kv-v2",
                 secret_binding_ref: "vault-secret://gemini/account/v1?token=sentinel"
               },
               %{},
               %{}
             )
  end

  test "managed materializer resolves durable Vault refs only inside the Auth effect task" do
    start_supervised!(ManagedStore)
    Auth.reset!()

    Auth.configure_managed_accounts!(
      store: ManagedStore,
      materializers: %{"gemini" => ManagedCredentialMaterializer}
    )

    Application.put_env(
      :jido_integration_secrets_provider,
      :managed_providers,
      %{
        "vault" => [
          address: "https://vault.internal",
          token_loader: fn -> "vault-token-sentinel" end,
          http_client: VaultHTTP
        ]
      }
    )

    now = ~U[2026-07-15 15:00:00Z]

    assert {:ok, %{account: account, account_ref: account_ref}} =
             Auth.register_managed_account(managed_registration(now))

    context = managed_context(account, now)
    assert {:ok, lease} = Auth.request_managed_lease(account_ref, context)

    request =
      MaterializationRequest.new!(%{
        materialization_ref: "materialization://gemini/vault/1",
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
    expected_account_ref = account.account_ref

    assert {:ok, %{status: :used, account_ref: ^expected_account_ref}} =
             Auth.with_materialized_credential(
               lease,
               request,
               managed_redemption_context(context, now),
               fn material ->
                 send(parent, {:vault_materialized, self(), material.payload["api_key"]})
                 %{status: :used, account_ref: material.account_ref}
               end
             )

    assert_receive {:vault_materialized, materialization_pid, "vault-sentinel"}
    refute materialization_pid == self()

    assert {:ok, fetched_lease} =
             Auth.fetch_lease(lease.lease_id, %{tenant_id: account.tenant_id, now: now})

    assert fetched_lease.payload == %{}
    refute inspect(fetched_lease) =~ "vault-sentinel"
    refute inspect(fetched_lease) =~ "vault-token-sentinel"
  end

  defp managed_registration(now) do
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

  defp managed_context(%ManagedAccount{} = account, now) do
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

  defp managed_redemption_context(context, now) do
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
