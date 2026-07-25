defmodule Jido.Integration.V2.StoreLocal.LeaseStoreTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Auth.LeaseRecord
  alias Jido.Integration.V2.StoreLocal.LeaseStore
  alias Jido.Integration.V2.StoreLocal.Server
  alias Jido.Integration.V2.StoreLocal.TestSupport

  setup do
    previous_storage_dir =
      Application.fetch_env(:jido_integration_v2_store_local, :storage_dir)

    storage_dir = TestSupport.tmp_dir!()
    Application.put_env(:jido_integration_v2_store_local, :storage_dir, storage_dir)
    {:ok, server} = Server.start_link([])

    on_exit(fn ->
      if pid = Process.whereis(Server), do: GenServer.stop(pid)

      case previous_storage_dir do
        {:ok, value} ->
          Application.put_env(:jido_integration_v2_store_local, :storage_dir, value)

        :error ->
          Application.delete_env(:jido_integration_v2_store_local, :storage_dir)
      end

      TestSupport.cleanup!(storage_dir)
    end)

    %{server: server}
  end

  test "durably records lease redemption and materialization", %{server: server} do
    issued_at = ~U[2026-07-25 12:00:00Z]

    lease =
      LeaseRecord.new!(%{
        lease_id: "lease-local-callbacks",
        tenant_id: "tenant-local",
        credential_ref_id: "credential-ref-local",
        credential_id: "credential-local",
        connection_id: "connection-local",
        subject: "operator-local",
        scopes: ["repo"],
        payload_keys: ["access_token"],
        issued_at: issued_at,
        expires_at: DateTime.add(issued_at, 60, :second)
      })

    redeemed_at = DateTime.add(issued_at, 10, :second)
    materialized_at = DateTime.add(issued_at, 11, :second)

    assert :ok = LeaseStore.store_lease(lease)

    assert {:ok, redeemed} = LeaseStore.record_redemption(lease.lease_id, redeemed_at, 1)
    assert redeemed.redemption_count == 1
    assert redeemed.last_redeemed_at == redeemed_at

    assert {:error, :max_calls_exceeded} =
             LeaseStore.record_redemption(lease.lease_id, materialized_at, 1)

    assert {:ok, materialized} =
             LeaseStore.record_materialization(
               lease.lease_id,
               "materialization-local-1",
               materialized_at
             )

    assert materialized.last_materialization_ref == "materialization-local-1"
    assert materialized.metadata.last_materialized_at == materialized_at

    GenServer.stop(server)
    assert {:ok, _server} = Server.start_link([])
    assert {:ok, ^materialized} = LeaseStore.fetch_lease(lease.lease_id)
  end
end
