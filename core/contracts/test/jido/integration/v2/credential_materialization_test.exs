defmodule Jido.Integration.V2.CredentialMaterializationTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.{ManagedAccountRef, MaterializationRequest, SecretMaterial}

  defp account(generation \\ 3) do
    ManagedAccountRef.new!(
      provider_family: "gemini",
      account_ref: "account://google/acme-primary",
      tenant_id: "tenant://acme",
      connection_id: "connection://jido/gemini/acme-primary",
      endpoint_ref: "endpoint://google/gemini-api",
      quota_scope_ref: "quota://google/acme-primary",
      generation: generation,
      fence: 11
    )
  end

  defp request do
    MaterializationRequest.new!(
      materialization_ref: "materialization://jido/run-1/attempt-1",
      lease_id: "lease://jido/run-1/attempt-1",
      account: account(),
      effect_ref: "effect://mezzanine/model/run-1",
      operation_ref: "operation://jido/gemini/generate-content",
      authority_ref: "grant://citadel/model/run-1",
      endpoint_ref: "endpoint://google/gemini-api",
      target_ref: "target://nshkr/local",
      issued_at: ~U[2026-07-15 12:00:00Z],
      expires_at: ~U[2026-07-15 12:05:00Z]
    )
  end

  test "binds materialization to an exact account generation and expiry" do
    materialization = request()

    assert MaterializationRequest.valid_for?(
             materialization,
             account(),
             ~U[2026-07-15 12:01:00Z]
           )

    refute MaterializationRequest.valid_for?(
             materialization,
             account(4),
             ~U[2026-07-15 12:01:00Z]
           )

    refute MaterializationRequest.valid_for?(
             materialization,
             account(),
             materialization.expires_at
           )
  end

  test "rejects invalid lease windows and generation zero" do
    assert {:error, :invalid_managed_account_ref} =
             ManagedAccountRef.new(
               provider_family: "gemini",
               account_ref: "account://google/acme-primary",
               tenant_id: "tenant://acme",
               connection_id: "connection://jido/gemini/acme-primary",
               endpoint_ref: "endpoint://google/gemini-api",
               quota_scope_ref: "quota://google/acme-primary",
               generation: 0,
               fence: 11
             )

    attrs = request() |> Map.from_struct() |> Map.put(:expires_at, ~U[2026-07-15 12:00:00Z])
    assert {:error, :invalid_materialization_request} = MaterializationRequest.new(attrs)

    assert {:error, :invalid_materialization_request} =
             request()
             |> Map.from_struct()
             |> Map.put(:api_key, "sentinel-secret")
             |> MaterializationRequest.new()
  end

  test "secret material is redacted from inspection and rejects durable JSON encoding" do
    material =
      SecretMaterial.new!(
        materialization_ref: "materialization://jido/run-1/attempt-1",
        provider_family: "gemini",
        account_ref: "account://google/acme-primary",
        generation: 3,
        payload: %{"api_key" => "sentinel-secret"}
      )

    refute inspect(material) =~ "sentinel-secret"
    assert SecretMaterial.redacted(material).payload == "[REDACTED]"

    assert_raise ArgumentError, ~r/cannot be durably encoded/, fn -> Jason.encode!(material) end
  end

  test "materializer behavior exposes only materialize and revoke" do
    callbacks =
      Jido.Integration.V2.CredentialMaterializer.behaviour_info(:callbacks) |> MapSet.new()

    assert callbacks == MapSet.new([{:materialize, 2}, {:revoke, 2}])
  end
end
