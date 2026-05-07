defmodule Jido.Integration.V2.ControlPlanePersistenceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.ControlPlane.Persistence
  alias Jido.Integration.V2.ControlPlane.RunLedger
  alias Jido.Integration.V2.ControlPlane.Stores

  setup do
    Persistence.reset!()
    :ok
  end

  test "defaults control-plane stores to mickey mouse memory without host config" do
    assert {:ok, resolution} = Persistence.resolve([])
    assert resolution.profile.id == :mickey_mouse
    assert resolution.profile.default_tier == :memory_ephemeral
    assert resolution.durable? == false
    assert resolution.store_modules.run_store == RunLedger
    assert Stores.run_store() == RunLedger
  end

  test "refuses durable control-plane selection without an explicit capability" do
    assert {:error, {:missing_store_capability, :postgres_shared}} =
             Persistence.resolve(profile: :integration_postgres)
  end

  test "records tenant provider connector partitions for run routing" do
    partition =
      Persistence.partition(
        tenant_ref: "tenant://tenant-1",
        provider_family: "linear",
        connector_instance_ref: "connector-instance://tenant-1/linear/a",
        data_class: :run_truth
      )

    assert partition.tenant_ref == "tenant://tenant-1"
    assert partition.provider_family == "linear"
    assert partition.connector_instance_ref == "connector-instance://tenant-1/linear/a"
    assert partition.data_class == :run_truth
  end
end
