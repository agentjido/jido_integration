defmodule Jido.Integration.V2.MemoryFragmentTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.MemoryFragment
  alias Jido.Integration.V2.SubjectRef

  test "private fragment preserves immutable lineage, effective access, content, and embedding fields" do
    evidence = evidence_ref("private-evidence")

    fragment =
      MemoryFragment.new!(%{
        fragment_id: "fragment-private-1",
        tenant_ref: "tenant-1",
        source_node_ref: "node://ji_1@127.0.0.1/node-a",
        tier: :private,
        t_epoch: 7,
        creating_user_ref: "user-1",
        user_ref: "user-1",
        source_agents: ["agent-1"],
        source_resources: ["resource-1"],
        source_scopes: ["scope-1"],
        access_agents: ["agent-1"],
        access_resources: ["resource-1"],
        access_scopes: ["scope-1"],
        access_projection_hash: "sha256:" <> String.duplicate("a", 64),
        applied_policies: ["policy://write/private/v1"],
        evidence_refs: [evidence],
        governance_refs: [],
        parent_fragment_id: nil,
        content_hash: "sha256:" <> String.duplicate("b", 64),
        content_ref: %{store: "object", key: "memory/private/1"},
        schema_ref: "schema://memory/private/v1",
        embedding: [0.1, 0.2, 0.3],
        embedding_model_ref: "embedding://model/text-embedding-3-small",
        embedding_dimension: 3,
        redaction_summary: %{classification: "none"},
        confidence: 0.91,
        retention_class: "standard",
        metadata: %{source: "unit-test"}
      })

    assert fragment.contract_name == "Platform.MemoryFragment.V1"
    assert fragment.contract_version == "1.0.0"

    assert MemoryFragment.dump(fragment) == %{
             contract_name: "Platform.MemoryFragment.V1",
             contract_version: "1.0.0",
             fragment_id: "fragment-private-1",
             tenant_ref: "tenant-1",
             source_node_ref: "node://ji_1@127.0.0.1/node-a",
             tier: :private,
             t_epoch: 7,
             creating_user_ref: "user-1",
             user_ref: "user-1",
             scope_ref: nil,
             installation_ref: nil,
             source_agents: ["agent-1"],
             source_resources: ["resource-1"],
             source_scopes: ["scope-1"],
             access_agents: ["agent-1"],
             access_resources: ["resource-1"],
             access_scopes: ["scope-1"],
             access_projection_hash: "sha256:" <> String.duplicate("a", 64),
             applied_policies: ["policy://write/private/v1"],
             evidence_refs: [EvidenceRef.dump(evidence)],
             governance_refs: [],
             parent_fragment_id: nil,
             content_hash: "sha256:" <> String.duplicate("b", 64),
             content_ref: %{store: "object", key: "memory/private/1"},
             schema_ref: "schema://memory/private/v1",
             embedding: [0.1, 0.2, 0.3],
             embedding_model_ref: "embedding://model/text-embedding-3-small",
             embedding_dimension: 3,
             share_up_policy_ref: nil,
             transform_pipeline: [],
             non_identity_transform_count: 0,
             promotion_decision_ref: nil,
             promotion_policy_ref: nil,
             rebuild_spec: nil,
             derived_state_attachment_ref: nil,
             redaction_summary: %{classification: "none"},
             confidence: 0.91,
             retention_class: "standard",
             expires_at: nil,
             metadata: %{source: "unit-test"}
           }
  end

  test "shared fragment requires parent lineage and a trusted non-identity transform count" do
    attrs =
      base_attrs(:shared)
      |> Map.merge(%{
        scope_ref: "scope-1",
        parent_fragment_id: "fragment-private-1",
        share_up_policy_ref: "policy://share-up/v1",
        transform_pipeline: [%{kind: "summarize", transform_ref: "transform://summarize/v1"}],
        non_identity_transform_count: 1
      })

    assert %MemoryFragment{tier: :shared} = MemoryFragment.new!(attrs)

    assert_raise ArgumentError, ~r/non_identity_transform_count must be greater than 0/, fn ->
      attrs
      |> Map.put(:non_identity_transform_count, 0)
      |> MemoryFragment.new!()
    end

    assert_raise ArgumentError, ~r/parent_fragment_id is required for shared tier/, fn ->
      attrs
      |> Map.delete(:parent_fragment_id)
      |> MemoryFragment.new!()
    end
  end

  test "governed fragment requires evidence, governance, promotion decision, and rebuild spec" do
    attrs =
      base_attrs(:governed)
      |> Map.merge(%{
        installation_ref: "installation-1",
        evidence_refs: [evidence_ref("governed-evidence")],
        governance_refs: [governance_ref("promotion-approval")],
        promotion_decision_ref: "promotion://decision/1",
        promotion_policy_ref: "policy://promote/v1",
        rebuild_spec: %{strategy: "from_evidence", evidence_refs: ["governed-evidence"]},
        derived_state_attachment_ref: "jido://v2/derived_state_attachment/run/run-1"
      })

    assert %MemoryFragment{tier: :governed} = MemoryFragment.new!(attrs)

    assert_raise ArgumentError, ~r/evidence_refs must be non-empty for governed tier/, fn ->
      attrs
      |> Map.put(:evidence_refs, [])
      |> MemoryFragment.new!()
    end

    assert_raise ArgumentError, ~r/governance_refs must be non-empty for governed tier/, fn ->
      attrs
      |> Map.put(:governance_refs, [])
      |> MemoryFragment.new!()
    end

    assert_raise ArgumentError, ~r/rebuild_spec is required for governed tier/, fn ->
      attrs
      |> Map.delete(:rebuild_spec)
      |> MemoryFragment.new!()
    end
  end

  test "fragment rejects private wrong-user provenance and mismatched embedding dimension" do
    assert_raise ArgumentError, ~r/creating_user_ref must equal user_ref for private tier/, fn ->
      :private
      |> base_attrs()
      |> Map.merge(%{creating_user_ref: "user-2", user_ref: "user-1"})
      |> MemoryFragment.new!()
    end

    assert_raise ArgumentError, ~r/embedding_dimension must match embedding length/, fn ->
      :private
      |> base_attrs()
      |> Map.merge(%{embedding: [0.1, 0.2], embedding_dimension: 3})
      |> MemoryFragment.new!()
    end
  end

  defp base_attrs(tier) do
    %{
      fragment_id: "fragment-#{tier}-1",
      tenant_ref: "tenant-1",
      source_node_ref: "node://ji_1@127.0.0.1/node-a",
      tier: tier,
      t_epoch: 9,
      creating_user_ref: "user-1",
      user_ref: "user-1",
      source_agents: ["agent-1"],
      source_resources: ["resource-1"],
      source_scopes: ["scope-1"],
      access_agents: ["agent-1"],
      access_resources: ["resource-1"],
      access_scopes: ["scope-1"],
      access_projection_hash: "sha256:" <> String.duplicate("c", 64),
      applied_policies: ["policy://phase7/#{tier}"],
      evidence_refs: [evidence_ref("evidence-#{tier}")],
      governance_refs: [],
      content_hash: "sha256:" <> String.duplicate("d", 64),
      content_ref: %{store: "object", key: "memory/#{tier}/1"},
      schema_ref: "schema://memory/#{tier}/v1",
      embedding: [0.4, 0.5, 0.6],
      embedding_model_ref: "embedding://model/test",
      embedding_dimension: 3
    }
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
