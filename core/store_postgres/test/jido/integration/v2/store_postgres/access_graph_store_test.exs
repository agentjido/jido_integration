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
               committed_at: committed_at
             )

    assert Enum.map(edges, & &1.epoch_start) == [1, 1, 1]
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
               committed_at: DateTime.add(committed_at, 1, :second)
             )

    assert AccessGraphStore.current_epoch("tenant-1") == 2
    assert AccessGraphStore.epoch_at("tenant-1", committed_at) == 1
  end

  test "controlled revocation closes an edge at a fresh epoch without mutating identity fields" do
    assert {:ok, %{edges: [edge]}} =
             AccessGraphStore.insert_edges(
               "tenant-1",
               [edge_attrs(:ua, "user-1", "agent-1")],
               cause: "grant"
             )

    assert AccessGraphStore.a_of("tenant-1", "user-1", 1) == MapSet.new(["agent-1"])

    assert {:ok, revoked} =
             AccessGraphStore.revoke_edge(edge.edge_id, governance_ref("revoke-1"),
               cause: "lease_revoked"
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
               cause: "missing_authority"
             )

    assert message =~ "granting_authority_ref is required"

    assert {:error, %ArgumentError{message: message}} =
             AccessGraphStore.insert_edges(
               "tenant-1",
               [edge_attrs(:us, "user-1", "scope-a")],
               cause: "cycle",
               scope_hierarchy_edges: [{"scope-a", "scope-b"}, {"scope-b", "scope-a"}]
             )

    assert message =~ "scope hierarchy cycle"

    assert {:ok, %{edges: [edge]}} =
             AccessGraphStore.insert_edges(
               "tenant-1",
               [edge_attrs(:ua, "user-1", "agent-1")],
               cause: "grant"
             )

    assert {:error, changeset} =
             %AccessGraphEpochRecord{}
             |> AccessGraphEpochRecord.changeset(%{
               tenant_ref: "tenant-1",
               epoch: 1,
               cause: "manual_duplicate",
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
