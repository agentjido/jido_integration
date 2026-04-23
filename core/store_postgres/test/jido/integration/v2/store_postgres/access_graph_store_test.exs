defmodule Jido.Integration.V2.StorePostgres.AccessGraphStoreTest do
  use Jido.Integration.V2.StorePostgres.DataCase

  alias Jido.Integration.V2.AccessGraph
  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.StorePostgres.AccessGraphStore
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.AccessGraphEdgeRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.AccessGraphEpochRecord
  alias Jido.Integration.V2.SubjectRef

  test "allocates one monotonic epoch per committed graph transaction and derives graph views" do
    committed_at = ~U[2026-04-23 10:00:00Z]

    assert {:ok, %{epoch: 1, edges: edges}} =
             AccessGraphStore.insert_edges(
               "tenant-1",
               [
                 edge_attrs(:ua, "user-1", "agent-1"),
                 edge_attrs(:ar, "agent-1", "resource-1"),
                 edge_attrs(:us, "user-1", "scope-1")
               ],
               cause: "installation_activation",
               trace_id: "trace-1",
               committed_at: committed_at,
               source_node_ref: "node://ji_1@127.0.0.1/node-a"
             )

    assert Enum.map(edges, & &1.epoch_start) == [1, 1, 1]

    assert Enum.map(edges, & &1.source_node_ref) ==
             [
               "node://ji_1@127.0.0.1/node-a",
               "node://ji_1@127.0.0.1/node-a",
               "node://ji_1@127.0.0.1/node-a"
             ]

    epoch_record = Repo.get_by!(AccessGraphEpochRecord, tenant_ref: "tenant-1", epoch: 1)
    assert epoch_record.source_node_ref == "node://ji_1@127.0.0.1/node-a"
    assert is_binary(epoch_record.commit_lsn)

    assert %{"w" => _, "l" => _, "n" => "node://ji_1@127.0.0.1/node-a"} =
             epoch_record.commit_hlc

    assert AccessGraphStore.current_epoch("tenant-1") == 1
    assert AccessGraphStore.epoch_at("tenant-1", committed_at) == 1
    assert AccessGraphStore.a_of("tenant-1", "user-1", 1) == MapSet.new(["agent-1"])
    assert AccessGraphStore.r_of("tenant-1", "agent-1", 1) == MapSet.new(["resource-1"])
    assert AccessGraphStore.s_of("tenant-1", "user-1", 1) == MapSet.new(["scope-1"])

    tuple = %{
      access_agents: ["agent-1"],
      access_resources: ["resource-1"],
      access_scopes: ["scope-1"]
    }

    assert AccessGraphStore.graph_admissible?("tenant-1", tuple, "user-1", "agent-1", 1)

    assert {:ok, %{epoch: 2}} =
             AccessGraphStore.insert_edges(
               "tenant-1",
               [edge_attrs(:up, "user-1", "policy-1")],
               cause: "policy_activation",
               committed_at: DateTime.add(committed_at, 1, :second),
               source_node_ref: "node://ji_2@127.0.0.1/node-b"
             )

    assert AccessGraphStore.current_epoch("tenant-1") == 2
    assert AccessGraphStore.epoch_at("tenant-1", committed_at) == 1
  end

  test "controlled revocation closes an edge at a fresh epoch without mutating identity fields" do
    assert {:ok, %{edges: [edge]}} =
             AccessGraphStore.insert_edges(
               "tenant-1",
               [edge_attrs(:ua, "user-1", "agent-1")],
               cause: "grant",
               source_node_ref: "node://ji_1@127.0.0.1/node-a"
             )

    assert AccessGraphStore.a_of("tenant-1", "user-1", 1) == MapSet.new(["agent-1"])

    assert {:ok, revoked} =
             AccessGraphStore.revoke_edge(edge.edge_id, governance_ref("revoke-1"),
               cause: "lease_revoked",
               source_node_ref: "node://ji_2@127.0.0.1/node-b"
             )

    assert revoked.epoch_start == 1
    assert revoked.epoch_end == 2
    assert revoked.revoking_authority_ref.ref == "jido://v2/governance/policy_decision/revoke-1"
    assert AccessGraphStore.a_of("tenant-1", "user-1", 1) == MapSet.new(["agent-1"])
    assert AccessGraphStore.a_of("tenant-1", "user-1", 2) == MapSet.new()
  end

  test "store rejects missing authority, duplicate epoch, scope cycles, and direct identity mutation" do
    assert {:error, %ArgumentError{message: message}} =
             AccessGraphStore.insert_edges(
               "tenant-1",
               [edge_attrs(:ua, "user-1", "agent-1") |> Map.delete(:granting_authority_ref)],
               cause: "missing_authority",
               source_node_ref: "node://ji_1@127.0.0.1/node-a"
             )

    assert message =~ "granting_authority_ref is required"

    assert {:error, %ArgumentError{message: message}} =
             AccessGraphStore.insert_edges(
               "tenant-1",
               [edge_attrs(:us, "user-1", "scope-a")],
               cause: "cycle",
               source_node_ref: "node://ji_1@127.0.0.1/node-a",
               scope_hierarchy_edges: [{"scope-a", "scope-b"}, {"scope-b", "scope-a"}]
             )

    assert message =~ "scope hierarchy cycle"

    assert {:ok, %{edges: [edge]}} =
             AccessGraphStore.insert_edges(
               "tenant-1",
               [edge_attrs(:ua, "user-1", "agent-1")],
               cause: "grant",
               source_node_ref: "node://ji_1@127.0.0.1/node-a"
             )

    assert {:error, changeset} =
             %AccessGraphEpochRecord{}
             |> AccessGraphEpochRecord.changeset(%{
               tenant_ref: "tenant-1",
               epoch: 1,
               cause: "manual_duplicate",
               source_node_ref: "node://ji_1@127.0.0.1/node-a",
               commit_lsn: "16/B374D848",
               commit_hlc: %{
                 "w" => 1_776_947_200_000_000_000,
                 "l" => 0,
                 "n" => "node://ji_1@127.0.0.1/node-a"
               },
               committed_at: ~U[2026-04-23 10:00:00Z]
             })
             |> Repo.insert()

    assert %{tenant_ref: [_message]} = errors_on(changeset)

    record = Repo.get!(AccessGraphEdgeRecord, edge.edge_id)

    assert_raise Postgrex.Error, ~r/immutable identity fields/, fn ->
      record
      |> AccessGraphEdgeRecord.changeset(%{edge_type: "ar"})
      |> Repo.update!()
    end

    assert_raise Postgrex.Error, ~r/immutable identity fields/, fn ->
      record
      |> AccessGraphEdgeRecord.changeset(%{source_node_ref: "node://ji_2@127.0.0.1/node-b"})
      |> Repo.update!()
    end
  end

  test "store rejects graph writes without source node refs and pins snapshot in repeatable-read helper" do
    assert {:error, %ArgumentError{message: message}} =
             AccessGraphStore.insert_edges(
               "tenant-1",
               [edge_attrs(:ua, "user-1", "agent-1") |> Map.delete(:source_node_ref)],
               cause: "missing_node"
             )

    assert message =~ "source_node_ref"

    assert {:ok, %{epoch: 1}} =
             AccessGraphStore.insert_edges(
               "tenant-1",
               [edge_attrs(:ua, "user-1", "agent-1")],
               cause: "grant",
               source_node_ref: "node://ji_1@127.0.0.1/node-a"
             )

    assert {:ok, snapshot} = AccessGraphStore.current_epoch_for_tenant("tenant-1")
    assert snapshot.snapshot_epoch == 1
    assert snapshot.tenant_ref == "tenant-1"
  end

  test "concurrent multi-node graph transactions produce distinct tenant epochs" do
    node_refs = [
      "node://ji_1@127.0.0.1/node-a",
      "node://ji_2@127.0.0.1/node-b"
    ]

    results =
      1..20
      |> Task.async_stream(
        fn index ->
          node_ref = Enum.at(node_refs, rem(index, 2))

          AccessGraphStore.insert_edges(
            "tenant-concurrent",
            [edge_attrs(:ua, "user-#{index}", "agent-#{index}")],
            cause: "concurrent-grant",
            source_node_ref: node_ref
          )
        end,
        max_concurrency: 4,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, {:ok, %{epoch: epoch, edges: [edge]}}} ->
        {epoch, edge.source_node_ref}
      end)

    epochs = Enum.map(results, &elem(&1, 0))
    assert Enum.sort(epochs) == Enum.to_list(1..20)
    assert MapSet.new(Enum.map(results, &elem(&1, 1))) == MapSet.new(node_refs)
  end

  test "backfill builder materializes TenantScope-style rows into initial edges" do
    edges =
      AccessGraph.backfill_from_tenant_scope!(
        %{
          tenant_id: "tenant-1",
          actor_ref: %{"user_ref" => "user-1"},
          installation_id: "installation-1"
        },
        agent_refs: ["agent-1"],
        resource_refs: ["resource-1"],
        scope_refs: ["scope-1"],
        policy_refs: ["policy-1"],
        source_node_ref: "node://ji_1@127.0.0.1/node-a",
        granting_authority_ref: governance_ref("backfill-grant"),
        evidence_refs: [evidence_ref("backfill-evidence")]
      )

    assert Enum.map(edges, & &1.edge_type) == [:ua, :ar, :us, :sr, :up]
  end

  defp edge_attrs(edge_type, head_ref, tail_ref, overrides \\ %{}) do
    Map.merge(
      %{
        edge_type: edge_type,
        head_ref: head_ref,
        tail_ref: tail_ref,
        source_node_ref: "node://ji_1@127.0.0.1/node-a",
        granting_authority_ref: governance_ref("grant-#{edge_type}-#{head_ref}-#{tail_ref}"),
        evidence_refs: [evidence_ref("evidence-#{edge_type}-#{head_ref}-#{tail_ref}")],
        policy_refs: ["policy://phase7/#{edge_type}"],
        metadata: %{}
      },
      overrides
    )
  end

  defp governance_ref(id) do
    GovernanceRef.new!(%{
      kind: :policy_decision,
      id: id,
      subject: subject_ref(),
      evidence: [evidence_ref("governance-evidence-#{id}")],
      metadata: %{status: :allowed}
    })
  end

  defp evidence_ref(id) do
    EvidenceRef.new!(%{
      kind: :event,
      id: id,
      packet_ref: "jido://v2/review_packet/run/run-1",
      subject: subject_ref(),
      metadata: %{phase: 7}
    })
  end

  defp subject_ref do
    SubjectRef.new!(%{kind: :run, id: "run-1", metadata: %{tenant_ref: "tenant-1"}})
  end
end
