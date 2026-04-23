defmodule Jido.Integration.V2.MemorySnapshotContextTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.ClockOrdering.HLC
  alias Jido.Integration.V2.Memory.SnapshotContext

  test "snapshot context preserves one bound epoch and ordering evidence" do
    context =
      SnapshotContext.new!(%{
        tenant_ref: "tenant-1",
        snapshot_epoch: 11,
        pinned_at: ~U[2026-04-23 12:00:00Z],
        source_node_ref: "node://ji_1@127.0.0.1/node-a",
        commit_lsn: "16/B374D848",
        commit_hlc:
          HLC.new!(%{
            wall_ns: 1_776_947_200_000_000_000,
            logical: 0,
            source_node_ref: "node://ji_1@127.0.0.1/node-a"
          }),
        latency_us: 123
      })

    assert SnapshotContext.dump(context) == %{
             contract_name: "Platform.Memory.SnapshotContext.V1",
             contract_version: "1.0.0",
             tenant_ref: "tenant-1",
             snapshot_epoch: 11,
             pinned_at: "2026-04-23T12:00:00Z",
             source_node_ref: "node://ji_1@127.0.0.1/node-a",
             commit_lsn: "16/B374D848",
             commit_hlc: %{
               "w" => 1_776_947_200_000_000_000,
               "l" => 0,
               "n" => "node://ji_1@127.0.0.1/node-a"
             },
             latency_us: 123
           }
  end
end
