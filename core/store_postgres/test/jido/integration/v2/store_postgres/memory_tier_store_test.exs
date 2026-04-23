defmodule Jido.Integration.V2.StorePostgres.MemoryTierStoreTest do
  use Jido.Integration.V2.StorePostgres.DataCase

  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.MemoryFragment
  alias Jido.Integration.V2.StorePostgres.MemoryTierStore
  alias Jido.Integration.V2.StorePostgres.Repo

  alias Jido.Integration.V2.StorePostgres.Schemas.{
    MemoryGovernedRecord,
    MemoryPrivateRecord,
    MemorySharedRecord
  }

  alias Jido.Integration.V2.SubjectRef

  test "inserts and queries private, shared, and governed fragments through separate tier stores" do
    private_attrs = private_fragment_attrs("fragment-private-1", [0.9, 0.1, 0.0])
    shared_attrs = shared_fragment_attrs("fragment-shared-1", [0.1, 0.9, 0.0])
    governed_attrs = governed_fragment_attrs("fragment-governed-1", [0.1, 0.0, 0.9])

    assert {:ok, %MemoryFragment{tier: :private} = private} =
             MemoryTierStore.insert_private_fragment(private_attrs)

    assert {:ok, %MemoryFragment{tier: :shared} = shared} =
             MemoryTierStore.insert_shared_fragment(shared_attrs)

    assert {:ok, %MemoryFragment{tier: :governed} = governed} =
             MemoryTierStore.insert_governed_fragment(governed_attrs)

    assert Enum.map(MemoryTierStore.private_fragments("tenant-1", "user-1"), & &1.fragment_id) ==
             [private.fragment_id]

    assert Enum.map(MemoryTierStore.shared_fragments("tenant-1", "scope-1"), & &1.fragment_id) ==
             [shared.fragment_id]

    assert Enum.map(
             MemoryTierStore.governed_fragments("tenant-1", "installation-1"),
             & &1.fragment_id
           ) == [governed.fragment_id]

    assert [%MemoryFragment{fragment_id: "fragment-private-1"}] =
             MemoryTierStore.nearest_private_fragments("tenant-1", "user-1", [1.0, 0.0, 0.0],
               limit: 1
             )
  end

  test "database constraints reject invalid private, shared, and governed tier records" do
    assert {:error, changeset} =
             %MemoryPrivateRecord{}
             |> MemoryPrivateRecord.changeset(
               private_fragment_attrs("fragment-private-bad-user")
               |> Map.merge(%{creating_user_ref: "user-2"})
             )
             |> Repo.insert()

    assert %{creating_user_ref: [_message]} = errors_on(changeset)

    assert {:error, changeset} =
             %MemorySharedRecord{}
             |> MemorySharedRecord.changeset(
               shared_fragment_attrs("fragment-shared-identity")
               |> Map.merge(%{non_identity_transform_count: 0})
             )
             |> Repo.insert()

    assert %{non_identity_transform_count: [_message]} = errors_on(changeset)

    assert {:error, changeset} =
             %MemoryGovernedRecord{}
             |> MemoryGovernedRecord.changeset(
               governed_fragment_attrs("fragment-governed-missing-evidence")
               |> Map.merge(%{evidence_refs: []})
             )
             |> Repo.insert()

    assert %{evidence_refs: [_message]} = errors_on(changeset)
  end

  test "database trigger rejects provenance column updates after insert" do
    assert {:ok, %MemoryFragment{fragment_id: fragment_id}} =
             MemoryTierStore.insert_private_fragment(
               private_fragment_attrs("fragment-private-immut")
             )

    record = Repo.get!(MemoryPrivateRecord, fragment_id)

    assert_raise Postgrex.Error,
                 ~r/memory_private immutable provenance fields cannot be updated/,
                 fn ->
                   record
                   |> MemoryPrivateRecord.changeset(%{source_agents: ["agent-2"]})
                   |> Repo.update!()
                 end
  end

  defp private_fragment_attrs(fragment_id, embedding \\ [0.3, 0.2, 0.1]) do
    base_attrs(fragment_id, :private, embedding)
    |> Map.merge(%{
      user_ref: "user-1",
      creating_user_ref: "user-1",
      evidence_refs: [evidence_ref("evidence-#{fragment_id}")],
      governance_refs: []
    })
  end

  defp shared_fragment_attrs(fragment_id, embedding \\ [0.2, 0.3, 0.1]) do
    base_attrs(fragment_id, :shared, embedding)
    |> Map.merge(%{
      scope_ref: "scope-1",
      parent_fragment_id: "fragment-private-parent",
      share_up_policy_ref: "policy://share-up/v1",
      transform_pipeline: [%{kind: "summarize", transform_ref: "transform://summarize/v1"}],
      non_identity_transform_count: 1
    })
  end

  defp governed_fragment_attrs(fragment_id, embedding \\ [0.1, 0.2, 0.3]) do
    base_attrs(fragment_id, :governed, embedding)
    |> Map.merge(%{
      installation_ref: "installation-1",
      evidence_refs: [evidence_ref("evidence-#{fragment_id}")],
      governance_refs: [governance_ref("governance-#{fragment_id}")],
      promotion_decision_ref: "promotion://decision/#{fragment_id}",
      promotion_policy_ref: "policy://promote/v1",
      rebuild_spec: %{strategy: "from_evidence", fragment_id: fragment_id},
      derived_state_attachment_ref: "jido://v2/derived_state_attachment/run/run-1"
    })
  end

  defp base_attrs(fragment_id, tier, embedding) do
    %{
      fragment_id: fragment_id,
      tenant_ref: "tenant-1",
      tier: tier,
      t_epoch: 11,
      source_agents: ["agent-1"],
      source_resources: ["resource-1"],
      source_scopes: ["scope-1"],
      access_agents: ["agent-1"],
      access_resources: ["resource-1"],
      access_scopes: ["scope-1"],
      access_projection_hash: "sha256:" <> String.duplicate("e", 64),
      applied_policies: ["policy://phase7/#{tier}"],
      evidence_refs: [evidence_ref("evidence-base-#{fragment_id}")],
      governance_refs: [],
      content_hash: "sha256:" <> String.duplicate("f", 64),
      content_ref: %{store: "object", key: "memory/#{tier}/#{fragment_id}"},
      schema_ref: "schema://memory/#{tier}/v1",
      embedding: embedding,
      embedding_model_ref: "embedding://model/test",
      embedding_dimension: length(embedding),
      redaction_summary: %{},
      retention_class: "standard",
      metadata: %{test: true}
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
    |> GovernanceRef.dump()
  end

  defp evidence_ref(id) do
    EvidenceRef.new!(%{
      kind: :event,
      id: id,
      packet_ref: "jido://v2/review_packet/run/run-1",
      subject: subject_ref(),
      metadata: %{phase: 7}
    })
    |> EvidenceRef.dump()
  end

  defp subject_ref do
    SubjectRef.new!(%{kind: :run, id: "run-1", metadata: %{tenant_ref: "tenant-1"}})
  end
end
