defmodule Jido.Integration.V2.StorePostgres.AccessGraphStoreTest do
  use Jido.Integration.V2.StorePostgres.DataCase

  import Ecto.Query

  alias Jido.Integration.V2.AccessGraph
  alias Jido.Integration.V2.ClusterInvalidation
  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.StorePostgres.AccessGraphStore
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.AccessGraphEdgeRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.AccessGraphEpochRecord
  alias Jido.Integration.V2.SubjectRef

  test "allocates one monotonic epoch per committed graph transaction and derives graph views" do
    telemetry_id = attach_invalidation_telemetry()
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

    assert_receive {:cluster_invalidation, %{message: message}}
    assert message.invalidation_id == "graph-invalidation://tenant-1/1"
    assert message.tenant_ref == "tenant-1"
    assert message.source_node_ref == epoch_record.source_node_ref
    assert message.commit_lsn == epoch_record.commit_lsn
    assert message.commit_hlc == epoch_record.commit_hlc
    assert message.topic == ClusterInvalidation.graph_topic!("tenant-1", 1)
    assert message.metadata["tenant_ref"] == "tenant-1"
    assert message.metadata["new_epoch"] == 1
    assert message.metadata["source_node_ref"] == epoch_record.source_node_ref
    assert message.metadata["commit_lsn"] == epoch_record.commit_lsn
    assert message.metadata["commit_hlc"] == epoch_record.commit_hlc

    assert AccessGraphStore.current_epoch("tenant-1") == 1
    assert AccessGraphStore.epoch_at("tenant-1", committed_at) == 1
    assert AccessGraphStore.a_of("tenant-1", "user-1", 1) == MapSet.new(["agent-1"])
    assert AccessGraphStore.r_of("tenant-1", "agent-1", 1) == MapSet.new(["resource-1"])
    assert AccessGraphStore.s_of("tenant-1", "user-1", 1) == MapSet.new(["scope-1"])
    assert AccessGraphStore.sr_of("tenant-1", "scope-1", 1) == MapSet.new()

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

    assert_receive {:cluster_invalidation, %{message: %{topic: topic}}}
    assert topic == ClusterInvalidation.graph_topic!("tenant-1", 2)

    :telemetry.detach(telemetry_id)
  end

  test "authority compile view reads graph policy edges and rejects stale epochs by default" do
    assert {:ok, %{epoch: 1}} =
             AccessGraphStore.insert_edges(
               "tenant-auth",
               [
                 edge_attrs(:ua, "user-auth", "agent-auth"),
                 edge_attrs(:ar, "agent-auth", "resource-auth"),
                 edge_attrs(:us, "user-auth", "scope-auth"),
                 edge_attrs(:sr, "scope-auth", "resource-auth"),
                 edge_attrs(:up, "user-auth", "policy-auth")
               ],
               cause: "installation_activation",
               trace_id: "trace-auth",
               source_node_ref: "node://ji_1@127.0.0.1/node-a"
             )

    tuple = %{
      access_agents: ["agent-auth"],
      access_resources: ["resource-auth"],
      access_scopes: ["scope-auth"],
      policy_refs: ["policy-auth"]
    }

    assert {:ok, view} =
             AccessGraphStore.authority_compile_view(
               "tenant-auth",
               "user-auth",
               "agent-auth",
               1,
               tuple
             )

    assert view.snapshot_epoch == 1
    assert view.access_agents == MapSet.new(["agent-auth"])
    assert view.access_resources == MapSet.new(["resource-auth"])
    assert view.access_scopes == MapSet.new(["scope-auth"])
    assert view.scope_resources == MapSet.new(["resource-auth"])
    assert view.policy_refs == MapSet.new(["policy-auth"])
    assert view.graph_admissible?

    assert {:ok, %{epoch: 2}} =
             AccessGraphStore.insert_edges(
               "tenant-auth",
               [edge_attrs(:up, "user-auth", "policy-new")],
               cause: "policy_compilation_change",
               source_node_ref: "node://ji_2@127.0.0.1/node-b"
             )

    assert {:error, {:stale_epoch, %{requested_epoch: 1, current_epoch: 2}}} =
             AccessGraphStore.authority_compile_view(
               "tenant-auth",
               "user-auth",
               "agent-auth",
               1,
               tuple
             )

    assert {:ok, stale_allowed_view} =
             AccessGraphStore.authority_compile_view(
               "tenant-auth",
               "user-auth",
               "agent-auth",
               1,
               tuple,
               allow_stale?: true
             )

    assert stale_allowed_view.snapshot_epoch == 1
    assert stale_allowed_view.policy_refs == MapSet.new(["policy-auth"])
  end

  test "explicit epoch advancement publishes graph invalidation with commit evidence" do
    telemetry_id = attach_invalidation_telemetry()
    source_node_ref = "node://ji_2@127.0.0.1/node-b"

    assert {:ok,
            %{
              tenant_ref: "tenant-advance",
              epoch: 1,
              source_node_ref: ^source_node_ref,
              commit_lsn: commit_lsn,
              commit_hlc: %{"n" => ^source_node_ref}
            }} =
             AccessGraphStore.advance_epoch("tenant-advance",
               cause: "policy_compilation_change",
               trace_id: "trace-policy-change",
               source_node_ref: source_node_ref
             )

    assert is_binary(commit_lsn)

    assert_receive {:cluster_invalidation, %{message: message}}
    assert message.topic == ClusterInvalidation.graph_topic!("tenant-advance", 1)
    assert message.metadata["cause"] == "policy_compilation_change"
    assert message.metadata["commit_lsn"] == commit_lsn
    assert message.metadata["commit_hlc"]["n"] == source_node_ref

    :telemetry.detach(telemetry_id)
  end

  test "controlled revocation closes an edge at a fresh epoch without mutating identity fields" do
    telemetry_id = attach_invalidation_telemetry()

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

    assert_receive {:cluster_invalidation, %{message: %{topic: topic}}}
    assert topic == ClusterInvalidation.graph_topic!("tenant-1", 1)

    assert_receive {:cluster_invalidation, %{message: %{topic: topic}}}
    assert topic == ClusterInvalidation.graph_topic!("tenant-1", 2)

    :telemetry.detach(telemetry_id)
  end

  test "revokes user and tenant edges with access graph invalidation metadata" do
    telemetry_id = attach_invalidation_telemetry()

    assert {:ok, %{epoch: 1}} =
             AccessGraphStore.insert_edges(
               "tenant-1",
               [
                 edge_attrs(:ua, "user-delete", "agent-1"),
                 edge_attrs(:us, "user-delete", "scope-1"),
                 edge_attrs(:ar, "agent-1", "resource-1")
               ],
               cause: "grant",
               source_node_ref: "node://ji_1@127.0.0.1/node-a"
             )

    assert {:ok, %{epoch: 2, revoked_edges: revoked_edges}} =
             AccessGraphStore.revoke_subject_edges(
               "tenant-1",
               "user-delete",
               governance_ref("delete-user"),
               cause: "user_deletion",
               trace_id: "trace-delete-user",
               source_node_ref: "node://ji_2@127.0.0.1/node-b"
             )

    assert Enum.map(revoked_edges, &{&1.edge_type, &1.head_ref, &1.epoch_end}) == [
             {:ua, "user-delete", 2},
             {:us, "user-delete", 2}
           ]

    assert AccessGraphStore.a_of("tenant-1", "user-delete", 2) == MapSet.new()
    assert AccessGraphStore.s_of("tenant-1", "user-delete", 2) == MapSet.new()
    assert AccessGraphStore.r_of("tenant-1", "agent-1", 2) == MapSet.new(["resource-1"])

    assert_receive {:cluster_invalidation, %{message: %{topic: initial_topic}}}
    assert initial_topic == ClusterInvalidation.graph_topic!("tenant-1", 1)

    assert_receive {:cluster_invalidation, %{message: user_delete_message}}
    assert user_delete_message.topic == ClusterInvalidation.graph_topic!("tenant-1", 2)
    assert user_delete_message.source_node_ref == "node://ji_2@127.0.0.1/node-b"
    assert is_binary(user_delete_message.commit_lsn)
    assert %{"n" => "node://ji_2@127.0.0.1/node-b"} = user_delete_message.commit_hlc
    assert user_delete_message.metadata["tenant_ref"] == "tenant-1"
    assert user_delete_message.metadata["new_epoch"] == 2
    assert user_delete_message.metadata["source_node_ref"] == user_delete_message.source_node_ref
    assert user_delete_message.metadata["commit_lsn"] == user_delete_message.commit_lsn
    assert user_delete_message.metadata["commit_hlc"] == user_delete_message.commit_hlc
    assert user_delete_message.metadata["cause"] == "user_deletion"

    assert {:ok, %{epoch: 1}} =
             AccessGraphStore.insert_edges(
               "tenant-offboard",
               [
                 edge_attrs(:ua, "user-tenant", "agent-tenant"),
                 edge_attrs(:ar, "agent-tenant", "resource-tenant")
               ],
               cause: "grant",
               source_node_ref: "node://ji_1@127.0.0.1/node-a"
             )

    assert {:ok, %{epoch: 2, revoked_edges: tenant_revoked_edges}} =
             AccessGraphStore.revoke_tenant_edges(
               "tenant-offboard",
               governance_ref("offboard-tenant"),
               cause: "tenant_offboarding",
               source_node_ref: "node://ji_2@127.0.0.1/node-b"
             )

    assert Enum.map(tenant_revoked_edges, & &1.epoch_end) == [2, 2]
    assert AccessGraphStore.a_of("tenant-offboard", "user-tenant", 2) == MapSet.new()
    assert AccessGraphStore.r_of("tenant-offboard", "agent-tenant", 2) == MapSet.new()

    assert_receive {:cluster_invalidation, %{message: %{topic: tenant_initial_topic}}}
    assert tenant_initial_topic == ClusterInvalidation.graph_topic!("tenant-offboard", 1)

    assert_receive {:cluster_invalidation, %{message: tenant_message}}
    assert tenant_message.topic == ClusterInvalidation.graph_topic!("tenant-offboard", 2)
    assert tenant_message.metadata["tenant_ref"] == "tenant-offboard"
    assert tenant_message.metadata["new_epoch"] == 2
    assert tenant_message.metadata["cause"] == "tenant_offboarding"

    :telemetry.detach(telemetry_id)
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

  test "snapshot-bound graph views keep one pinned epoch through revocation" do
    assert {:ok, %{epoch: 1}} =
             AccessGraphStore.insert_edges(
               "tenant-1",
               [
                 edge_attrs(:ua, "user-1", "agent-1"),
                 edge_attrs(:ar, "agent-1", "resource-1"),
                 edge_attrs(:us, "user-1", "scope-1")
               ],
               cause: "grant",
               source_node_ref: "node://ji_1@127.0.0.1/node-a"
             )

    assert {:ok, snapshot} = AccessGraphStore.current_epoch_for_tenant("tenant-1")

    [edge] =
      AccessGraphEdgeRecord
      |> where([edge], edge.edge_type == "ua")
      |> Repo.all()

    assert {:ok, _revoked} =
             AccessGraphStore.revoke_edge(edge.edge_id, governance_ref("revoke-snapshot"),
               cause: "lease_revoked",
               source_node_ref: "node://ji_2@127.0.0.1/node-b"
             )

    tuple = %{
      access_agents: ["agent-1"],
      access_resources: ["resource-1"],
      access_scopes: ["scope-1"]
    }

    assert %{
             snapshot_epoch: 1,
             access_agents: access_agents,
             access_resources: access_resources,
             access_scopes: access_scopes,
             graph_admissible?: true
           } = AccessGraphStore.snapshot_views(snapshot, "user-1", "agent-1", tuple)

    assert access_agents == MapSet.new(["agent-1"])
    assert access_resources == MapSet.new(["resource-1"])
    assert access_scopes == MapSet.new(["scope-1"])
    assert AccessGraphStore.a_of("tenant-1", "user-1", 2) == MapSet.new()
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

  test "lists node-aware graph events by trace and detects HLC-resolved wall-clock inversions" do
    assert {:ok, %{epoch: 1}} =
             AccessGraphStore.insert_edges(
               "tenant-order",
               [edge_attrs(:ua, "user-order", "agent-order")],
               cause: "grant-a",
               trace_id: "trace-order",
               committed_at: ~U[2026-04-23 10:00:02Z],
               commit_hlc: %{
                 "w" => 1_776_954_000_000_000_001,
                 "l" => 0,
                 "n" => "node://ji_1@127.0.0.1/node-a"
               },
               source_node_ref: "node://ji_1@127.0.0.1/node-a"
             )

    assert {:ok, %{epoch: 2}} =
             AccessGraphStore.insert_edges(
               "tenant-order",
               [edge_attrs(:ar, "agent-order", "resource-order")],
               cause: "grant-b",
               trace_id: "trace-order",
               committed_at: ~U[2026-04-23 10:00:01Z],
               commit_hlc: %{
                 "w" => 1_776_954_000_000_000_002,
                 "l" => 0,
                 "n" => "node://ji_2@127.0.0.1/node-b"
               },
               source_node_ref: "node://ji_2@127.0.0.1/node-b"
             )

    assert [
             %{epoch: 1, source_node_ref: "node://ji_1@127.0.0.1/node-a"},
             %{epoch: 2, source_node_ref: "node://ji_2@127.0.0.1/node-b"}
           ] = AccessGraphStore.list_epoch_events_by_trace("trace-order")

    assert [%{epoch: 2, cause: "grant-b"}] =
             AccessGraphStore.list_epoch_events_by_tenant("tenant-order",
               epoch: 2,
               source_node_ref: "node://ji_2@127.0.0.1/node-b"
             )

    assert [
             %{
               previous_epoch: 1,
               current_epoch: 2,
               resolved_by: :commit_hlc
             }
           ] = AccessGraphStore.wall_clock_inversions("trace-order")
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

  defp attach_invalidation_telemetry do
    handler_id = {__MODULE__, self(), make_ref()}

    :telemetry.attach(
      handler_id,
      [:jido_integration, :cluster_invalidation, :publish],
      fn _event, _measurements, metadata, _config ->
        send(self(), {:cluster_invalidation, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    handler_id
  end
end
