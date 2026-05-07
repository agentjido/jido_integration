defmodule Jido.Integration.V2.StorePostgres.PersistencePolicyTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.StorePostgres

  test "exposes an explicit postgres capability for durable opt-in" do
    assert {:ok, capability} = StorePostgres.store_capability()
    assert capability.tier == :postgres_shared
    assert capability.durable?
    assert capability.restart_safe?
  end

  test "fails durable preflight before repo mutation when capability is missing" do
    assert {:error, {:missing_store_capability, :postgres_shared}} =
             StorePostgres.preflight(profile: :integration_postgres, capabilities: [])
  end

  test "fails durable preflight before repo mutation when migration proof is missing" do
    {:ok, capability} = StorePostgres.store_capability()

    assert {:error, {:missing_migration_proof, :jido_integration_store_postgres}} =
             StorePostgres.preflight(profile: :integration_postgres, capabilities: [capability])
  end

  test "passes durable preflight when capability and migration proof are present" do
    {:ok, capability} = StorePostgres.store_capability()

    assert :ok =
             StorePostgres.preflight(
               profile: :integration_postgres,
               capabilities: [capability],
               migration_proof: :present
             )
  end
end
