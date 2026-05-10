defmodule Jido.Integration.V2.AuthPersistenceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Auth.Persistence
  alias Jido.Integration.V2.Auth.Store
  alias Jido.Integration.V2.Auth.Stores

  @auth_store_keys [:credential_store, :lease_store, :connection_store, :install_store]

  setup do
    previous_env = snapshot_env()

    Enum.each(@auth_store_keys, fn key ->
      Application.delete_env(:jido_integration_v2_auth, key)
    end)

    Persistence.reset!()

    on_exit(fn ->
      Persistence.reset!()
      restore_env(previous_env)
    end)

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

  defp snapshot_env do
    Map.new(@auth_store_keys, fn key ->
      {key, Application.fetch_env(:jido_integration_v2_auth, key)}
    end)
  end

  defp restore_env(previous_env) do
    Enum.each(previous_env, fn
      {key, {:ok, value}} -> Application.put_env(:jido_integration_v2_auth, key, value)
      {key, :error} -> Application.delete_env(:jido_integration_v2_auth, key)
    end)
  end
end
