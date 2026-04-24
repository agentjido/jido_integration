defmodule Jido.Integration.V2.ClockOrderingHLCTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.ClockOrdering.HLC

  @node_a "node://ji_1@127.0.0.1/node-a"
  @node_b "node://ji_2@127.0.0.1/node-b"

  test "local events advance logical counter when wall time is equal" do
    first = HLC.local_event(nil, @node_a, 1_000)
    second = HLC.local_event(first, @node_a, 1_000)

    assert first.wall_ns == 1_000
    assert first.logical == 0
    assert second.wall_ns == 1_000
    assert second.logical == 1
    assert HLC.compare(first, second) == :lt
  end

  test "remote merge follows HLC merge algorithm and canonical serialization" do
    local = HLC.new!(%{wall_ns: 2_000, logical: 3, source_node_ref: @node_a})
    remote = HLC.new!(%{wall_ns: 2_000, logical: 7, source_node_ref: @node_b})

    assert {:ok, merged} = HLC.merge_remote(local, remote, @node_a, 2_000)
    assert merged.wall_ns == 2_000
    assert merged.logical == 8
    assert merged.source_node_ref == @node_a
    assert HLC.dump(merged) == %{"w" => 2_000, "l" => 8, "n" => @node_a}
    assert HLC.canonical_string(merged) == "2000.8.node%3A%2F%2Fji_1%40127.0.0.1%2Fnode-a"
  end

  test "remote merge rejects clock skew beyond sixty seconds" do
    local = HLC.new!(%{wall_ns: 1_000, logical: 0, source_node_ref: @node_a})
    remote = HLC.new!(%{wall_ns: 60_000_000_001 + 1_000, logical: 0, source_node_ref: @node_b})

    assert {:error,
            {:clock_skew_rejected,
             %{observed_remote_hlc_skew_ns: 60_000_000_001, event: :clock_skew_rejected},
             fallback}} = HLC.merge_remote(local, remote, @node_a, 1_000)

    assert fallback.source_node_ref == @node_a
    assert fallback.logical == 1
  end
end
