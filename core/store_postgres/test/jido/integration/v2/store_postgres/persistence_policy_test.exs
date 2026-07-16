defmodule Jido.Integration.V2.StorePostgres.PersistencePolicyTest do
  use Jido.Integration.V2.StorePostgres.DataCase

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

  test "passes durable preflight only after the live repo reports every migration up" do
    {:ok, capability} = StorePostgres.store_capability()

    assert :ok =
             StorePostgres.preflight(
               profile: :integration_postgres,
               capabilities: [capability]
             )
  end
end
