defmodule Jido.Integration.V2.AuthPersistenceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Auth.Persistence
  alias Jido.Integration.V2.Auth.Store
  alias Jido.Integration.V2.Auth.Stores

  setup do
    Persistence.reset!()
    :ok
  end

  test "defaults auth stores to mickey mouse memory without host config" do
    assert {:ok, resolution} = Persistence.resolve([])
    assert resolution.profile.id == :mickey_mouse
    assert resolution.profile.default_tier == :memory_ephemeral
    assert resolution.durable? == false
    assert resolution.store_modules.credential_store == Store
    assert Stores.credential_store() == Store
  end

  test "refuses durable auth selection without an explicit capability" do
    assert {:error, {:missing_store_capability, :postgres_shared}} =
             Persistence.resolve(profile: :integration_postgres)
  end

  test "records tenant provider connector partitions for lease routing" do
    partition =
      Persistence.partition(
        tenant_ref: "tenant://tenant-1",
        provider_family: "github",
        provider_account_ref: "provider-account://github/redacted",
        connector_instance_ref: "connector-instance://tenant-1/github/a"
      )

    assert partition.tenant_ref == "tenant://tenant-1"
    assert partition.provider_family == "github"
    assert partition.provider_account_ref == "provider-account://github/redacted"
    assert partition.connector_instance_ref == "connector-instance://tenant-1/github/a"
  end
end
