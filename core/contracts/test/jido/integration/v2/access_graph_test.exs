defmodule Jido.Integration.V2.AccessGraphTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AccessGraph
  alias Jido.Integration.V2.AccessGraph.Edge
  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.SubjectRef

  test "edge contract preserves identity, provenance, authority, and controlled close fields" do
    authority = governance_ref("grant-1")
    revocation = governance_ref("revoke-1")
    evidence = evidence_ref("evidence-1")

    edge =
      Edge.new!(%{
        edge_id: "edge-1",
        edge_type: :ua,
        head_ref: "user-1",
        tail_ref: "agent-1",
        tenant_ref: "tenant-1",
        epoch_start: 1,
        epoch_end: 3,
        granting_authority_ref: authority,
        revoking_authority_ref: revocation,
        evidence_refs: [evidence],
        policy_refs: ["policy://read/v1"],
        metadata: %{source: "test"}
      })

    assert Edge.dump(edge) == %{
             contract_name: "Platform.AccessGraph.Edge.v1",
             contract_version: "1.0.0",
             edge_id: "edge-1",
             edge_type: :ua,
             head_ref: "user-1",
             tail_ref: "agent-1",
             tenant_ref: "tenant-1",
             epoch_start: 1,
             epoch_end: 3,
             granting_authority_ref: GovernanceRef.dump(authority),
             revoking_authority_ref: GovernanceRef.dump(revocation),
             evidence_refs: [EvidenceRef.dump(evidence)],
             policy_refs: ["policy://read/v1"],
             metadata: %{source: "test"}
           }
  end

  test "edge contract rejects missing authority and invalid controlled close" do
    base = edge_attrs(:ua, "user-1", "agent-1")

    assert_raise ArgumentError, ~r/granting_authority_ref is required/, fn ->
      base
      |> Map.delete(:granting_authority_ref)
      |> Edge.new!()
    end

    assert_raise ArgumentError, ~r/epoch_end must be greater than epoch_start/, fn ->
      base
      |> Map.merge(%{epoch_start: 4, epoch_end: 4, revoking_authority_ref: governance_ref("r1")})
      |> Edge.new!()
    end

    assert_raise ArgumentError, ~r/revoking_authority_ref is required/, fn ->
      base
      |> Map.merge(%{epoch_start: 4, epoch_end: 5})
      |> Edge.new!()
    end
  end

  test "derived views and graph-only admissibility use active edges at epoch" do
    edges = [
      Edge.new!(edge_attrs(:ua, "user-1", "agent-1")),
      Edge.new!(edge_attrs(:ar, "agent-1", "resource-1")),
      Edge.new!(edge_attrs(:us, "user-1", "scope-1")),
      Edge.new!(
        edge_attrs(:ua, "user-1", "agent-revoked", %{
          epoch_end: 2,
          revoking_authority_ref: governance_ref("revoke-agent")
        })
      )
    ]

    assert AccessGraph.a_of(edges, "user-1", 1) ==
             MapSet.new(["agent-1", "agent-revoked"])

    assert AccessGraph.a_of(edges, "user-1", 2) == MapSet.new(["agent-1"])
    assert AccessGraph.r_of(edges, "agent-1", 2) == MapSet.new(["resource-1"])
    assert AccessGraph.s_of(edges, "user-1", 2) == MapSet.new(["scope-1"])

    tuple = %{
      access_agents: ["agent-1"],
      access_resources: ["resource-1"],
      access_scopes: ["scope-1"]
    }

    assert AccessGraph.graph_admissible?(edges, tuple, "user-1", "agent-1", 2)
    refute AccessGraph.graph_admissible?(edges, tuple, "user-1", "agent-2", 2)

    refute AccessGraph.graph_admissible?(
             edges,
             %{tuple | access_scopes: ["scope-2"]},
             "user-1",
             "agent-1",
             2
           )
  end

  test "scope hierarchy validation rejects cycles before graph writes" do
    assert :ok = AccessGraph.validate_scope_hierarchy!([{"scope-a", "scope-b"}])

    assert_raise ArgumentError, ~r/scope hierarchy cycle/, fn ->
      AccessGraph.validate_scope_hierarchy!([
        {"scope-a", "scope-b"},
        {"scope-b", "scope-c"},
        {"scope-c", "scope-a"}
      ])
    end
  end

  defp edge_attrs(edge_type, head_ref, tail_ref, overrides \\ %{}) do
    Map.merge(
      %{
        edge_id: "edge-#{edge_type}-#{head_ref}-#{tail_ref}",
        edge_type: edge_type,
        head_ref: head_ref,
        tail_ref: tail_ref,
        tenant_ref: "tenant-1",
        epoch_start: 1,
        granting_authority_ref: governance_ref("grant-#{edge_type}"),
        evidence_refs: [evidence_ref("evidence-#{edge_type}")],
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
