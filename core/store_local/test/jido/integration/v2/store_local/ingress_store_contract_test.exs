defmodule Jido.Integration.V2.StoreLocal.IngressStoreContractTest do
  use Jido.Integration.V2.StoreLocal.Case

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.StoreLocal.IngressStore
  alias Jido.Integration.V2.StoreLocal.RunStore

  test "round-trips trigger records and checkpoints" do
    run = run_fixture()
    trigger = trigger_record_fixture(%{run_id: run.run_id, dedupe_key: "dedupe-round-trip"})
    checkpoint = trigger_checkpoint_fixture(%{cursor: "cursor-round-trip"})

    assert :ok = RunStore.put_run(run)
    assert :ok = IngressStore.put_trigger(trigger)
    assert :ok = IngressStore.put_checkpoint(checkpoint)

    assert {:ok, persisted_trigger} =
             IngressStore.fetch_trigger(
               trigger.tenant_id,
               trigger.connector_id,
               trigger.trigger_id,
               trigger.dedupe_key
             )

    assert persisted_trigger.run_id == run.run_id
    assert persisted_trigger.signal["type"] == "github.issue.opened"

    assert {:ok, persisted_checkpoint} =
             IngressStore.fetch_checkpoint(
               checkpoint.tenant_id,
               checkpoint.connector_id,
               checkpoint.trigger_id,
               checkpoint.partition_key
             )

    assert persisted_checkpoint.cursor == "cursor-round-trip"
    assert persisted_checkpoint.revision == 1
  end

  test "updates checkpoints by composite key and increments revision" do
    checkpoint = trigger_checkpoint_fixture(%{cursor: "cursor-initial"})

    assert :ok = IngressStore.put_checkpoint(checkpoint)

    assert :ok =
             IngressStore.put_checkpoint(%{
               checkpoint
               | cursor: "cursor-updated",
                 last_event_id: "event-updated",
                 last_event_time: DateTime.add(checkpoint.last_event_time, 60, :second)
             })

    assert {:ok, persisted_checkpoint} =
             IngressStore.fetch_checkpoint(
               checkpoint.tenant_id,
               checkpoint.connector_id,
               checkpoint.trigger_id,
               checkpoint.partition_key
             )

    assert persisted_checkpoint.cursor == "cursor-updated"
    assert persisted_checkpoint.last_event_id == "event-updated"
    assert persisted_checkpoint.revision == 2
  end

  test "enforces durable dedupe scope uniqueness" do
    expires_at = DateTime.add(Contracts.now(), 86_400, :second)

    assert :ok =
             IngressStore.reserve_dedupe(
               "tenant-1",
               "github",
               "issues.opened",
               "dedupe-duplicate",
               expires_at
             )

    assert {:error, :duplicate} =
             IngressStore.reserve_dedupe(
               "tenant-1",
               "github",
               "issues.opened",
               "dedupe-duplicate",
               expires_at
             )
  end

  test "duplicate dedupe checks do not poison the surrounding transaction" do
    expires_at = DateTime.add(Contracts.now(), 86_400, :second)
    checkpoint = trigger_checkpoint_fixture(%{partition_key: "partition-transaction-safe"})

    assert :ok =
             IngressStore.transaction(fn ->
               assert :ok =
                        IngressStore.reserve_dedupe(
                          "tenant-1",
                          "github",
                          "issues.opened",
                          "dedupe-transaction-safe",
                          expires_at
                        )

               assert {:error, :duplicate} =
                        IngressStore.reserve_dedupe(
                          "tenant-1",
                          "github",
                          "issues.opened",
                          "dedupe-transaction-safe",
                          expires_at
                        )

               assert :ok = IngressStore.put_checkpoint(checkpoint)
               :ok
             end)

    assert {:ok, persisted_checkpoint} =
             IngressStore.fetch_checkpoint(
               checkpoint.tenant_id,
               checkpoint.connector_id,
               checkpoint.trigger_id,
               checkpoint.partition_key
             )

    assert persisted_checkpoint.cursor == checkpoint.cursor
  end

  test "rollback unwinds partial ingress transactions" do
    run = run_fixture()
    trigger = trigger_record_fixture(%{run_id: run.run_id, dedupe_key: "dedupe-rollback"})
    checkpoint = trigger_checkpoint_fixture(%{partition_key: "partition-rollback"})

    assert :ok = RunStore.put_run(run)

    assert {:error, :forced_rollback} =
             IngressStore.transaction(fn ->
               assert :ok = IngressStore.put_trigger(trigger)
               assert :ok = IngressStore.put_checkpoint(checkpoint)
               IngressStore.rollback(:forced_rollback)
             end)

    assert :error =
             IngressStore.fetch_trigger(
               trigger.tenant_id,
               trigger.connector_id,
               trigger.trigger_id,
               trigger.dedupe_key
             )

    assert :error =
             IngressStore.fetch_checkpoint(
               checkpoint.tenant_id,
               checkpoint.connector_id,
               checkpoint.trigger_id,
               checkpoint.partition_key
             )
  end

  test "recovers persisted ingress truth after restart" do
    expires_at = DateTime.add(Contracts.now(), 86_400, :second)
    run = run_fixture()
    trigger = trigger_record_fixture(%{run_id: run.run_id, dedupe_key: "dedupe-restart"})
    checkpoint = trigger_checkpoint_fixture(%{partition_key: "partition-restart"})

    assert :ok = RunStore.put_run(run)

    assert :ok =
             IngressStore.reserve_dedupe(
               trigger.tenant_id,
               trigger.connector_id,
               trigger.trigger_id,
               trigger.dedupe_key,
               expires_at
             )

    assert :ok = IngressStore.put_trigger(trigger)
    assert :ok = IngressStore.put_checkpoint(checkpoint)

    assert :ok = TestSupport.restart_store!()

    assert {:ok, ^trigger} =
             IngressStore.fetch_trigger(
               trigger.tenant_id,
               trigger.connector_id,
               trigger.trigger_id,
               trigger.dedupe_key
             )

    assert {:ok, recovered_checkpoint} =
             IngressStore.fetch_checkpoint(
               checkpoint.tenant_id,
               checkpoint.connector_id,
               checkpoint.trigger_id,
               checkpoint.partition_key
             )

    assert recovered_checkpoint.cursor == checkpoint.cursor

    assert {:error, :duplicate} =
             IngressStore.reserve_dedupe(
               trigger.tenant_id,
               trigger.connector_id,
               trigger.trigger_id,
               trigger.dedupe_key,
               expires_at
             )
  end
end
