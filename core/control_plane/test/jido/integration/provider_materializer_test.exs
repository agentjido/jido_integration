defmodule Jido.Integration.ProviderMaterializerTest do
  use ExUnit.Case, async: false

  alias Gemini.GovernedAuthority
  alias Jido.Integration.ProviderMaterializer
  alias Jido.Integration.V2.Auth.ManagedAccount

  alias Jido.Integration.V2.{
    CredentialLease,
    MaterializationRequest,
    SecretMaterial
  }

  @sentinel "managed-gemini-materializer-sentinel"

  test "projects exact redeemed Gemini material into one transient typed authority" do
    {request, material, binding} = fixture()

    assert {:ok, %GovernedAuthority{} = authority} =
             ProviderMaterializer.materialize(material, binding)

    assert {:ok, refs} = ProviderMaterializer.authority_refs(authority)
    assert refs.provider_ref == "gemini"
    assert refs.provider_family == request.account.provider_family
    assert refs.provider_account_ref == request.account.account_ref
    assert refs.model_account_ref == request.account.account_ref
    assert refs.credential_lease_ref == request.lease_id
    assert refs.endpoint_ref == request.endpoint_ref
    assert refs.authority_ref == request.authority_ref
    assert refs.operation_ref == request.operation_ref
    assert refs.target_ref == request.target_ref
    assert refs.generation == request.account.generation
    assert refs.fence == request.account.fence
    assert GovernedAuthority.credential_query_names(authority) == ["key"]
    assert GovernedAuthority.secret_values(authority) == [@sentinel]
    refute inspect(authority) =~ @sentinel
    assert_raise ArgumentError, ~r/transient/, fn -> Jason.encode!(authority.secret_material) end
  end

  test "fails closed before authority construction when account agreement diverges" do
    {_request, material, binding} = fixture()

    assert {:error, {:provider_materialization_mismatch, :model_account_ref}} =
             ProviderMaterializer.materialize(
               material,
               Map.put(binding, :model_account_ref, "provider-account://other")
             )

    assert {:error, {:provider_materialization_mismatch, :provider_family}} =
             ProviderMaterializer.materialize(%{material | provider_family: "openai"}, binding)
  end

  test "materializes one exact Codex auth root and removes it without leaking material" do
    {account, lease, request, material, binding, root_parent} = codex_fixture()
    previous = Application.get_env(:jido_integration_v2_control_plane, :codex_materializer)

    Application.put_env(
      :jido_integration_v2_control_plane,
      :codex_materializer,
      command: System.find_executable("true"),
      session_root_parent: root_parent
    )

    on_exit(fn ->
      restore_env(:codex_materializer, previous)
      File.rm_rf(root_parent)
    end)

    assert {:ok, %ProviderMaterializer.CodexBundle{} = bundle} =
             ProviderMaterializer.materialize_codex(
               material,
               lease,
               request,
               account,
               binding
             )

    assert File.dir?(bundle.cleanup_root)
    assert File.read!(Path.join(bundle.cleanup_root, "auth.json")) =~ "access_token"
    assert bundle.runtime.cwd == binding.workspace_root
    assert bundle.runtime.env == %{"CODEX_HOME" => bundle.cleanup_root}
    assert bundle.runtime.credential_lease_ref == lease.lease_id
    assert bundle.runtime.provider_account_ref == account.account_ref
    assert bundle.runtime.workspace_ref == binding.workspace_ref
    refute inspect(bundle) =~ @sentinel
    refute inspect(bundle.secret_material) =~ @sentinel

    assert :ok = ProviderMaterializer.cleanup_codex(bundle)
    refute File.exists?(bundle.cleanup_root)
  end

  test "Codex materialization rejects target drift before creating a config root" do
    {account, lease, request, material, binding, root_parent} = codex_fixture()
    previous = Application.get_env(:jido_integration_v2_control_plane, :codex_materializer)

    Application.put_env(
      :jido_integration_v2_control_plane,
      :codex_materializer,
      command: System.find_executable("true"),
      session_root_parent: root_parent
    )

    on_exit(fn ->
      restore_env(:codex_materializer, previous)
      File.rm_rf(root_parent)
    end)

    assert {:error, {:codex_materialization_mismatch, :target_ref}} =
             ProviderMaterializer.materialize_codex(
               material,
               lease,
               request,
               account,
               %{binding | target_ref: "target://other"}
             )

    assert Path.wildcard(Path.join(root_parent, "jido-codex-*")) == []
  end

  defp fixture do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    request =
      MaterializationRequest.new!(%{
        materialization_ref: "materialization://gemini/run-1/attempt-1",
        lease_id: "lease://gemini/run-1/attempt-1",
        account: %{
          provider_family: "gemini",
          account_ref: "provider-account://tenant-acme/gemini/primary",
          tenant_id: "tenant://acme",
          connection_id: "connection://gemini/primary",
          endpoint_ref: "endpoint://gemini/generate-content",
          quota_scope_ref: "quota://gemini/primary",
          generation: 7,
          fence: 11
        },
        effect_ref: "effect://mezzanine/run-1/turn-1/model",
        operation_ref: "operation://gemini/generate-content/run-1/turn-1",
        authority_ref: "grant://citadel/gemini/run-1/turn-1",
        endpoint_ref: "endpoint://gemini/generate-content",
        target_ref: "target://gemini/public-api",
        issued_at: now,
        expires_at: DateTime.add(now, 60, :second)
      })

    material =
      SecretMaterial.new!(%{
        materialization_ref: request.materialization_ref,
        provider_family: request.account.provider_family,
        account_ref: request.account.account_ref,
        generation: request.account.generation,
        payload: %{api_key: @sentinel}
      })

    binding = %{
      base_url: "https://generativelanguage.googleapis.com",
      provider_ref: "gemini",
      model_account_ref: request.account.account_ref,
      credential_handle_ref: "credential-handle://gemini/primary/generation-7",
      operation_policy_ref: "policy://citadel/synapse-gemini-turn/v1",
      redaction_ref: "redaction://gemini/managed/v1",
      materialization_request: request,
      endpoint_ref: request.endpoint_ref,
      authority_ref: request.authority_ref,
      operation_ref: request.operation_ref,
      target_ref: request.target_ref,
      fence: request.account.fence
    }

    {request, material, binding}
  end

  defp codex_fixture do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    account =
      ManagedAccount.new!(%{
        provider_family: "codex",
        account_ref: "provider-account://tenant-acme/codex/primary",
        tenant_id: "tenant://acme",
        connection_id: "connection://codex/primary",
        endpoint_ref: "endpoint://codex/app-server",
        quota_scope_ref: "quota://codex/primary",
        generation: 3,
        fence: 5,
        credential_handle_ref: "credential-handle://codex/primary/generation-3",
        secret_provider_ref: "vault://nshkr/kv-v2",
        secret_binding_ref: "vault-secret://codex/primary",
        state: :active,
        inserted_at: now,
        updated_at: now
      })

    lease =
      CredentialLease.new!(%{
        lease_id: "lease://codex/effect-1",
        tenant_id: account.tenant_id,
        connection_id: account.connection_id,
        credential_ref_id: "credential://codex/primary",
        subject: "nshkr-runtime",
        scopes: ["tool:effect"],
        payload: %{},
        lease_fields: ["auth_json"],
        issued_at: now,
        expires_at: DateTime.add(now, 60, :second),
        metadata: %{}
      })

    request =
      MaterializationRequest.new!(%{
        materialization_ref: "materialization://codex/effect-1",
        lease_id: lease.lease_id,
        account: ManagedAccount.ref(account),
        effect_ref: "effect://mezzanine/effect-1",
        operation_ref: "operation://codex/file-create-or-replace/effect-1",
        authority_ref: "grant://citadel/tool-effect/effect-1",
        endpoint_ref: account.endpoint_ref,
        target_ref: "target://workspace/effect-1/named-file",
        issued_at: now,
        expires_at: DateTime.add(now, 45, :second)
      })

    material =
      SecretMaterial.new!(%{
        materialization_ref: request.materialization_ref,
        provider_family: "codex",
        account_ref: account.account_ref,
        generation: account.generation,
        payload: %{auth_json: %{access_token: @sentinel, token_type: "Bearer"}}
      })

    root_parent =
      Path.join(
        System.tmp_dir!(),
        "jido-codex-materializer-test-#{System.unique_integer([:positive])}"
      )

    workspace_root = Path.join(root_parent, "workspace")
    File.mkdir_p!(workspace_root)

    binding = %{
      authority_ref: request.authority_ref,
      target_ref: request.target_ref,
      operation_ref: request.operation_ref,
      connector_binding_ref: "connector-binding://jido/codex/effect-1",
      native_auth_assertion_ref: "native-auth-assertion://jido/codex/effect-1",
      workspace_ref: "workspace://tenant-acme/effect-1",
      workspace_root: workspace_root
    }

    {account, lease, request, material, binding, root_parent}
  end

  defp restore_env(key, nil),
    do: Application.delete_env(:jido_integration_v2_control_plane, key)

  defp restore_env(key, value),
    do: Application.put_env(:jido_integration_v2_control_plane, key, value)
end
