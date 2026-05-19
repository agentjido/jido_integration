defmodule Jido.Integration.V2.AuthPersistenceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Auth.Persistence
  alias Jido.Integration.V2.Auth.Store
  alias Jido.Integration.V2.Auth.Stores

  @auth_store_keys [:credential_store, :lease_store, :connection_store, :install_store]

  defmodule AlternateStore do
  end

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

  test "configured auth store modules are owned by the supervised resolver" do
    assert :ok =
             Persistence.configure!(
               profile: :mickey_mouse,
               store_modules: alternate_store_modules()
             )

    assert Stores.credential_store() == AlternateStore
    assert Stores.install_store() == AlternateStore
  end

  test "auth persistence owner restarts to boot defaults" do
    assert :ok =
             Persistence.configure!(
               profile: :mickey_mouse,
               store_modules: alternate_store_modules()
             )

    assert Stores.credential_store() == AlternateStore

    owner = Process.whereis(Persistence.Owner)
    ref = Process.monitor(owner)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^ref, :process, ^owner, :killed}, 1_000
    assert wait_for_owner(Persistence.Owner, owner)

    assert Stores.credential_store() == Store
  end

  test "refuses durable auth selection without an explicit capability" do
    assert {:error, {:missing_store_capability, :postgres_shared}} =
             Persistence.resolve(profile: :integration_postgres)
  end

  test "records tenant resource connector partitions for lease routing" do
    partition =
      Persistence.partition(
        tenant_ref: "tenant://tenant-1",
        resource_family: "github",
        resource_account_ref: "provider-account://github/redacted",
        resource_instance_ref: "connector-instance://tenant-1/github/a"
      )

    assert partition.tenant_ref == "tenant://tenant-1"
    assert partition.resource_family == "github"
    assert partition.resource_account_ref == "provider-account://github/redacted"
    assert partition.resource_instance_ref == "connector-instance://tenant-1/github/a"
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

  defp alternate_store_modules do
    Map.new(@auth_store_keys, &{&1, AlternateStore})
  end

  defp wait_for_owner(name, old_pid, attempts \\ 50)

  defp wait_for_owner(_name, _old_pid, 0), do: flunk("persistence owner did not restart")

  defp wait_for_owner(name, old_pid, attempts) do
    case Process.whereis(name) do
      pid when is_pid(pid) and pid != old_pid ->
        pid

      _other ->
        receive do
        after
          10 -> wait_for_owner(name, old_pid, attempts - 1)
        end
    end
  end
end
