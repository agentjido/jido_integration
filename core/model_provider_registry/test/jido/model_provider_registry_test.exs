defmodule Jido.ModelProviderRegistryTest do
  use ExUnit.Case, async: true

  alias Jido.ModelProviderRegistry

  test "rejects materialization without authority and operation policy" do
    assert {:error, {:missing_materialization_refs, missing}} =
             ModelProviderRegistry.materialize(base_attrs())

    assert :authority_ref in missing
    assert :operation_policy_ref in missing
  end

  test "rejects raw provider material and projects refs only" do
    assert {:error, {:raw_material_rejected, rejected}} =
             base_attrs()
             |> Map.merge(required_refs())
             |> Map.put(:raw_provider_payload, %{token: "secret"})
             |> Map.put(:api_key, "secret")
             |> ModelProviderRegistry.materialize()

    assert Enum.sort(rejected) == [:api_key, :raw_provider_payload]

    assert {:ok, receipt} =
             base_attrs()
             |> Map.merge(required_refs())
             |> ModelProviderRegistry.materialize()

    assert receipt.materialization_ref == "model-materialization://tenant-1/model/a/chat"
    assert receipt.raw_material_present? == false
    refute Map.has_key?(receipt, :api_key)
    refute Map.has_key?(receipt, :raw_provider_payload)
  end

  defp base_attrs do
    %{
      tenant_ref: "tenant://tenant-1",
      model_profile_ref: "model-profile://tenant-1/model/a",
      provider_ref: "provider://inference",
      endpoint_profile_ref: "endpoint-profile://tenant-1/inference/chat",
      operation_class: :propose,
      capability_set: [:chat, :streaming],
      cost_profile_ref: "cost-profile://tenant-1/inference/chat",
      context_window_ref: "context-window://tenant-1/inference/long",
      retention_posture_ref: "retention-posture://provider/redacted",
      materialization_posture: :mock
    }
  end

  defp required_refs do
    %{
      authority_ref: "authority://tenant-1/model/a/propose",
      operation_policy_ref: "operation-policy://tenant-1/model/propose"
    }
  end
end
