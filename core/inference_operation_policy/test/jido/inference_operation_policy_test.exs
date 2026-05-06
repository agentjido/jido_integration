defmodule Jido.InferenceOperationPolicyTest do
  use ExUnit.Case, async: true

  alias Jido.InferenceOperationPolicy

  test "binds governed operation classes to model profiles" do
    assert :propose in InferenceOperationPolicy.operation_classes()
    assert :evaluate in InferenceOperationPolicy.operation_classes()
    assert :route in InferenceOperationPolicy.operation_classes()
    assert :verify in InferenceOperationPolicy.operation_classes()
    assert :embed in InferenceOperationPolicy.operation_classes()
    assert :rerank in InferenceOperationPolicy.operation_classes()
    assert :tool_call in InferenceOperationPolicy.operation_classes()

    assert {:ok, policy} = InferenceOperationPolicy.new(policy_attrs())

    assert {:ok, receipt} =
             InferenceOperationPolicy.authorize(
               %{
                 tenant_ref: "tenant://tenant-1",
                 authority_ref: "authority://tenant-1/model/a/propose",
                 operation_class: :propose,
                 model_profile_ref: "model-profile://tenant-1/model/a",
                 capability_set: [:chat, :streaming]
               },
               policy
             )

    assert receipt.operation_policy_ref == "operation-policy://tenant-1/model/propose"
    assert receipt.model_profile_ref == "model-profile://tenant-1/model/a"
  end

  test "fails closed for ambient env, provider defaults, unsupported operation, and model mismatch" do
    assert {:ok, policy} = InferenceOperationPolicy.new(policy_attrs())

    assert {:error, {:raw_material_rejected, [:env]}} =
             InferenceOperationPolicy.new(Map.put(policy_attrs(), :env, "OPENAI_API_KEY"))

    assert {:error, {:provider_default_rejected, :default_model}} =
             InferenceOperationPolicy.authorize(
               request_attrs(%{default_model: "gpt-default"}),
               policy
             )

    assert {:error, {:operation_not_allowed, :reflect}} =
             InferenceOperationPolicy.authorize(
               request_attrs(%{operation_class: :reflect}),
               policy
             )

    assert {:error, {:model_profile_not_allowed, "model-profile://tenant-1/model/b"}} =
             InferenceOperationPolicy.authorize(
               request_attrs(%{model_profile_ref: "model-profile://tenant-1/model/b"}),
               policy
             )
  end

  defp policy_attrs do
    %{
      operation_policy_ref: "operation-policy://tenant-1/model/propose",
      tenant_ref: "tenant://tenant-1",
      authority_ref: "authority://tenant-1/model/a/propose",
      allowed_operations: [:propose, :evaluate, :route, :verify, :embed, :rerank, :tool_call],
      model_profile_refs: ["model-profile://tenant-1/model/a"],
      capability_requirements: %{propose: [:chat]},
      budget_ref: "budget://tenant-1/model/propose",
      target_ref: "target://tenant-1/model/propose"
    }
  end

  defp request_attrs(overrides) do
    Map.merge(
      %{
        tenant_ref: "tenant://tenant-1",
        authority_ref: "authority://tenant-1/model/a/propose",
        operation_class: :propose,
        model_profile_ref: "model-profile://tenant-1/model/a",
        capability_set: [:chat]
      },
      overrides
    )
  end
end
