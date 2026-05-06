defmodule Jido.ModelProviderRegistry.ProviderPoolTest do
  use ExUnit.Case, async: true

  alias Jido.ModelProviderRegistry.ProviderPool

  test "provider pools materialize through governed inference adapters only" do
    assert {:error, {:ungoverned_provider_slots, ["slot-1"]}} =
             ProviderPool.materialize(%{
               provider_pool_ref: "provider-pool://tenant-1/trinity/router",
               tenant_ref: "tenant://tenant-1",
               authority_ref: "authority://tenant-1/trinity/router",
               operation_policy_ref: "operation-policy://tenant-1/trinity/route",
               slots: [
                 %{
                   slot_ref: "slot-1",
                   model_profile_ref: "model-profile://tenant-1/model/a",
                   direct_provider_sdk: :openai
                 }
               ]
             })

    assert {:ok, pool} =
             ProviderPool.materialize(%{
               provider_pool_ref: "provider-pool://tenant-1/trinity/router",
               tenant_ref: "tenant://tenant-1",
               authority_ref: "authority://tenant-1/trinity/router",
               operation_policy_ref: "operation-policy://tenant-1/trinity/route",
               slots: [
                 %{
                   slot_ref: "slot-1",
                   model_profile_ref: "model-profile://tenant-1/model/a",
                   governed_adapter_ref: "governed-adapter://jido/inference",
                   inference_adapter_ref: "inference-adapter://jido/control-plane"
                 }
               ]
             })

    assert pool.raw_material_present? == false
    assert hd(pool.slots).governed_adapter_ref == "governed-adapter://jido/inference"
  end
end
