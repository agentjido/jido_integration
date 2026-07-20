defmodule Jido.Integration.ProviderMaterializerTest do
  use ExUnit.Case, async: true

  alias Gemini.GovernedAuthority
  alias Jido.Integration.ProviderMaterializer
  alias Jido.Integration.V2.{MaterializationRequest, SecretMaterial}

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
end
