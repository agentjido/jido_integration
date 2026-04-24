defmodule Jido.Integration.V2.NodeIdentityTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.NodeIdentity

  test "loads stable node ref and increments boot generation from persistent identity file" do
    base_dir = Path.join(System.tmp_dir!(), "node-identity-#{System.unique_integer([:positive])}")

    identity =
      NodeIdentity.load_or_start!("ji_1",
        base_dir: base_dir,
        host: "127.0.0.1",
        node_role: :memory_writer,
        deployment_ref: "deployment://phase7/test",
        release_manifest_ref: "release://phase7/m7a",
        started_at: ~U[2026-04-23 12:00:00Z]
      )

    restarted =
      NodeIdentity.load_or_start!("ji_1",
        base_dir: base_dir,
        host: "127.0.0.1",
        node_role: :memory_writer,
        deployment_ref: "deployment://phase7/test",
        release_manifest_ref: "release://phase7/m7a",
        started_at: ~U[2026-04-23 12:01:00Z]
      )

    assert identity.node_ref =~ "node://ji_1@127.0.0.1/"
    assert restarted.node_ref == identity.node_ref
    assert restarted.node_instance_id != identity.node_instance_id
    assert restarted.boot_generation == identity.boot_generation + 1
    assert NodeIdentity.replay_group(restarted) == {restarted.node_ref, restarted.boot_generation}
  end

  test "validates required node identity fields and bounded metadata" do
    assert_raise ArgumentError, ~r/node_ref.*non-empty/, fn ->
      NodeIdentity.new!(%{
        node_ref: "",
        node_instance_id: "instance-1",
        boot_generation: 1,
        node_role: :memory_writer,
        deployment_ref: "deployment://phase7/test",
        release_manifest_ref: "release://phase7/m7a",
        started_at: ~U[2026-04-23 12:00:00Z]
      })
    end

    assert_raise ArgumentError, ~r/node_role is required/, fn ->
      NodeIdentity.new!(%{
        node_ref: "node://ji_1@127.0.0.1/persistent",
        node_instance_id: "instance-1",
        boot_generation: 1,
        deployment_ref: "deployment://phase7/test",
        release_manifest_ref: "release://phase7/m7a",
        started_at: ~U[2026-04-23 12:00:00Z]
      })
    end

    assert_raise ArgumentError, ~r/metadata exceeds maximum encoded size/, fn ->
      NodeIdentity.new!(%{
        node_ref: "node://ji_1@127.0.0.1/persistent",
        node_instance_id: "instance-1",
        boot_generation: 1,
        node_role: :memory_writer,
        deployment_ref: "deployment://phase7/test",
        release_manifest_ref: "release://phase7/m7a",
        started_at: ~U[2026-04-23 12:00:00Z],
        metadata: %{"blob" => String.duplicate("x", 8193)}
      })
    end
  end
end
