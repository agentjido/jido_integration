defmodule Jido.Integration.V2.StorePostgres.AccessGraphStore do
  @moduledoc """
  Canonical Postgres access graph store.
  """

  import Ecto.Query

  alias Jido.Integration.V2.AccessGraph
  alias Jido.Integration.V2.AccessGraph.Edge
  alias Jido.Integration.V2.ClockOrdering.HLC
  alias Jido.Integration.V2.ClusterInvalidation
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.Memory.SnapshotContext
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.ClusterInvalidationPublisher
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.AccessGraphEdgeRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.AccessGraphEpochRecord

  @spec insert_edges(String.t(), [map() | keyword()], keyword()) ::
          {:ok, %{epoch: pos_integer(), edges: [Edge.t()]}} | {:error, term()}
  def insert_edges(tenant_ref, edge_attrs, opts \\ [])
      when is_binary(tenant_ref) and is_list(edge_attrs) and is_list(opts) do
    StorePostgres.assert_started!()

    Repo.transaction(fn ->
      AccessGraph.validate_scope_hierarchy!(Keyword.get(opts, :scope_hierarchy_edges, []))
      epoch_record = allocate_epoch!(tenant_ref, opts)
      epoch = epoch_record.epoch

      edges =
        Enum.map(edge_attrs, fn attrs ->
          attrs
          |> Map.new()
          |> Map.put(:tenant_ref, tenant_ref)
          |> Map.put(:epoch_start, epoch)
          |> Map.put(:source_node_ref, epoch_record.source_node_ref)
          |> Map.put_new(:edge_id, Contracts.next_id("access_graph_edge"))
          |> Edge.new!()
          |> insert_edge!()
        end)

      publish_graph_invalidation!(epoch_record)
      %{epoch: epoch, edges: edges}
    end)
    |> unwrap_transaction()
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec revoke_edge(String.t(), GovernanceRef.t() | map(), keyword()) ::
          {:ok, Edge.t()} | {:error, term()}
  def revoke_edge(edge_id, revoking_authority_ref, opts \\ [])
      when is_binary(edge_id) and is_list(opts) do
    StorePostgres.assert_started!()

    Repo.transaction(fn ->
      edge_record =
        AccessGraphEdgeRecord
        |> where([edge], edge.edge_id == ^edge_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      revoke_edge_record!(edge_record, revoking_authority_ref, opts)
    end)
    |> unwrap_transaction()
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec revoke_subject_edges(String.t(), String.t(), GovernanceRef.t() | map(), keyword()) ::
          {:ok, %{epoch: non_neg_integer(), revoked_edges: [Edge.t()]}} | {:error, term()}
  def revoke_subject_edges(tenant_ref, subject_ref, revoking_authority_ref, opts \\ [])
      when is_binary(tenant_ref) and is_binary(subject_ref) and is_list(opts) do
    StorePostgres.assert_started!()

    Repo.transaction(fn ->
      records =
        AccessGraphEdgeRecord
        |> where(
          [edge],
          edge.tenant_ref == ^tenant_ref and is_nil(edge.epoch_end) and
            (edge.head_ref == ^subject_ref or edge.tail_ref == ^subject_ref)
        )
        |> order_by([edge], asc: edge.epoch_start, asc: edge.edge_id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      revoke_edge_records!(tenant_ref, records, revoking_authority_ref, opts)
    end)
    |> unwrap_transaction()
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec revoke_tenant_edges(String.t(), GovernanceRef.t() | map(), keyword()) ::
          {:ok, %{epoch: non_neg_integer(), revoked_edges: [Edge.t()]}} | {:error, term()}
  def revoke_tenant_edges(tenant_ref, revoking_authority_ref, opts \\ [])
      when is_binary(tenant_ref) and is_list(opts) do
    StorePostgres.assert_started!()

    Repo.transaction(fn ->
      records =
        AccessGraphEdgeRecord
        |> where([edge], edge.tenant_ref == ^tenant_ref and is_nil(edge.epoch_end))
        |> order_by([edge], asc: edge.epoch_start, asc: edge.edge_id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      revoke_edge_records!(tenant_ref, records, revoking_authority_ref, opts)
    end)
    |> unwrap_transaction()
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec current_epoch(String.t()) :: non_neg_integer()
  def current_epoch(tenant_ref) when is_binary(tenant_ref) do
    StorePostgres.assert_started!()

    AccessGraphEpochRecord
    |> where([epoch], epoch.tenant_ref == ^tenant_ref)
    |> select([epoch], max(epoch.epoch))
    |> Repo.one()
    |> case do
      nil -> 0
      epoch -> epoch
    end
  end

  @spec current_epoch_for_tenant(String.t(), keyword()) ::
          {:ok, SnapshotContext.t()} | {:error, :snapshot_pin_timeout | term()}
  def current_epoch_for_tenant(tenant_ref, opts \\ [])
      when is_binary(tenant_ref) and is_list(opts) do
    StorePostgres.assert_started!()

    timeout_ms = Keyword.get(opts, :timeout_ms, 5_000)
    started = System.monotonic_time(:microsecond)

    task =
      Task.async(fn ->
        Repo.transaction(
          fn ->
            epoch_record =
              AccessGraphEpochRecord
              |> where([epoch], epoch.tenant_ref == ^tenant_ref)
              |> order_by([epoch],
                desc: epoch.epoch,
                desc: epoch.commit_lsn,
                desc: fragment("(?->>'w')::bigint", epoch.commit_hlc),
                desc: fragment("(?->>'l')::bigint", epoch.commit_hlc),
                desc: epoch.source_node_ref
              )
              |> limit(1)
              |> Repo.one()

            snapshot_from_epoch_record(tenant_ref, epoch_record)
          end,
          isolation: :repeatable_read,
          timeout: timeout_ms
        )
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %SnapshotContext{} = snapshot}} ->
        snapshot = %{snapshot | latency_us: elapsed_us(started)}
        emit_snapshot_pin_telemetry(snapshot, :ok)
        {:ok, snapshot}

      {:ok, {:error, reason}} ->
        {:error, reason}

      nil ->
        latency_us = elapsed_us(started)

        :telemetry.execute(
          [:memsim, :recall, :snapshot_pin, :latency],
          %{duration: latency_us},
          %{tenant_ref: tenant_ref, status: :timeout}
        )

        {:error, :snapshot_pin_timeout}
    end
  end

  @spec epoch_at(String.t(), DateTime.t()) :: non_neg_integer()
  def epoch_at(tenant_ref, %DateTime{} = committed_at) when is_binary(tenant_ref) do
    StorePostgres.assert_started!()

    AccessGraphEpochRecord
    |> where([epoch], epoch.tenant_ref == ^tenant_ref and epoch.committed_at <= ^committed_at)
    |> select([epoch], max(epoch.epoch))
    |> Repo.one()
    |> case do
      nil -> 0
      epoch -> epoch
    end
  end

  @spec a_of(String.t(), String.t(), pos_integer()) :: MapSet.t(String.t())
  def a_of(tenant_ref, user_ref, epoch), do: active_tails(tenant_ref, :ua, user_ref, epoch)

  @spec r_of(String.t(), String.t(), pos_integer()) :: MapSet.t(String.t())
  def r_of(tenant_ref, agent_ref, epoch), do: active_tails(tenant_ref, :ar, agent_ref, epoch)

  @spec s_of(String.t(), String.t(), pos_integer()) :: MapSet.t(String.t())
  def s_of(tenant_ref, user_ref, epoch), do: active_tails(tenant_ref, :us, user_ref, epoch)

  @spec graph_admissible?(
          String.t(),
          AccessGraph.effective_access_tuple(),
          String.t(),
          String.t(),
          pos_integer()
        ) ::
          boolean()
  def graph_admissible?(tenant_ref, effective_access_tuple, user_ref, agent_ref, epoch) do
    tenant_ref
    |> active_edges(epoch)
    |> AccessGraph.graph_admissible?(effective_access_tuple, user_ref, agent_ref, epoch)
  end

  @spec snapshot_views(
          SnapshotContext.t(),
          String.t(),
          String.t(),
          AccessGraph.effective_access_tuple()
        ) :: %{
          snapshot_epoch: non_neg_integer(),
          access_agents: MapSet.t(String.t()),
          access_resources: MapSet.t(String.t()),
          access_scopes: MapSet.t(String.t()),
          graph_admissible?: boolean()
        }
  def snapshot_views(
        %SnapshotContext{tenant_ref: tenant_ref, snapshot_epoch: snapshot_epoch},
        user_ref,
        agent_ref,
        effective_access_tuple \\ %{}
      )
      when is_binary(tenant_ref) and is_integer(snapshot_epoch) and is_binary(user_ref) and
             is_binary(agent_ref) do
    %{
      snapshot_epoch: snapshot_epoch,
      access_agents: a_of(tenant_ref, user_ref, snapshot_epoch),
      access_resources: r_of(tenant_ref, agent_ref, snapshot_epoch),
      access_scopes: s_of(tenant_ref, user_ref, snapshot_epoch),
      graph_admissible?:
        graph_admissible?(
          tenant_ref,
          effective_access_tuple,
          user_ref,
          agent_ref,
          snapshot_epoch
        )
    }
  end

  @spec replay_views(
          String.t(),
          String.t(),
          String.t(),
          pos_integer(),
          AccessGraph.effective_access_tuple()
        ) :: %{
          snapshot_epoch: pos_integer(),
          access_agents: MapSet.t(String.t()),
          access_resources: MapSet.t(String.t()),
          access_scopes: MapSet.t(String.t()),
          graph_admissible?: boolean()
        }
  def replay_views(tenant_ref, user_ref, agent_ref, epoch, effective_access_tuple \\ %{})
      when is_binary(tenant_ref) and is_binary(user_ref) and is_binary(agent_ref) and
             is_integer(epoch) do
    %{
      snapshot_epoch: epoch,
      access_agents: a_of(tenant_ref, user_ref, epoch),
      access_resources: r_of(tenant_ref, agent_ref, epoch),
      access_scopes: s_of(tenant_ref, user_ref, epoch),
      graph_admissible?:
        graph_admissible?(tenant_ref, effective_access_tuple, user_ref, agent_ref, epoch)
    }
  end

  @spec list_epoch_events_by_trace(String.t()) :: [map()]
  def list_epoch_events_by_trace(trace_id) when is_binary(trace_id) do
    StorePostgres.assert_started!()

    AccessGraphEpochRecord
    |> where([epoch], epoch.trace_id == ^trace_id)
    |> order_by_commit()
    |> Repo.all()
    |> Enum.map(&to_epoch_event/1)
  end

  @spec list_epoch_events_by_tenant(String.t(), keyword()) :: [map()]
  def list_epoch_events_by_tenant(tenant_ref, opts \\ [])
      when is_binary(tenant_ref) and is_list(opts) do
    StorePostgres.assert_started!()

    AccessGraphEpochRecord
    |> where([epoch], epoch.tenant_ref == ^tenant_ref)
    |> maybe_filter_epoch(Keyword.get(opts, :epoch))
    |> maybe_filter_source_node(Keyword.get(opts, :source_node_ref))
    |> order_by_commit()
    |> Repo.all()
    |> Enum.map(&to_epoch_event/1)
  end

  @spec wall_clock_inversions(String.t()) :: [map()]
  def wall_clock_inversions(trace_id) when is_binary(trace_id) do
    trace_id
    |> list_epoch_events_by_trace()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [previous, current] ->
      DateTime.compare(current.committed_at, previous.committed_at) == :lt
    end)
    |> Enum.map(fn [previous, current] ->
      %{
        previous_tenant_ref: previous.tenant_ref,
        previous_epoch: previous.epoch,
        previous_committed_at: previous.committed_at,
        previous_commit_hlc: previous.commit_hlc,
        current_tenant_ref: current.tenant_ref,
        current_epoch: current.epoch,
        current_committed_at: current.committed_at,
        current_commit_hlc: current.commit_hlc,
        resolved_by: :commit_hlc
      }
    end)
  end

  defp allocate_epoch!(tenant_ref, opts) do
    source_node_ref =
      opts
      |> Keyword.get(:source_node_ref)
      |> Contracts.validate_non_empty_string!("access_graph_epoch.source_node_ref")

    commit_hlc =
      opts
      |> Keyword.get(:commit_hlc, HLC.local_event(nil, source_node_ref))
      |> HLC.new!()
      |> HLC.dump()

    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["access_graph:" <> tenant_ref])

    epoch = current_epoch_in_transaction(tenant_ref) + 1
    commit_lsn = current_wal_lsn!()

    %AccessGraphEpochRecord{}
    |> AccessGraphEpochRecord.changeset(%{
      tenant_ref: tenant_ref,
      epoch: epoch,
      committed_at:
        Keyword.get(opts, :committed_at, DateTime.utc_now() |> DateTime.truncate(:microsecond)),
      cause: Keyword.get(opts, :cause, "graph_change"),
      trace_id: Keyword.get(opts, :trace_id),
      source_node_ref: source_node_ref,
      commit_lsn: commit_lsn,
      commit_hlc: commit_hlc,
      metadata: Keyword.get(opts, :metadata, %{})
    })
    |> Repo.insert!()
  end

  defp current_wal_lsn! do
    %{rows: [[commit_lsn]]} = Repo.query!("SELECT pg_current_wal_lsn()::text", [])
    commit_lsn
  end

  defp publish_graph_invalidation!(%AccessGraphEpochRecord{} = epoch_record) do
    message =
      ClusterInvalidation.new!(%{
        invalidation_id: "graph-invalidation://#{epoch_record.tenant_ref}/#{epoch_record.epoch}",
        tenant_ref: epoch_record.tenant_ref,
        topic: ClusterInvalidation.graph_topic!(epoch_record.tenant_ref, epoch_record.epoch),
        source_node_ref: epoch_record.source_node_ref,
        commit_lsn: epoch_record.commit_lsn,
        commit_hlc: epoch_record.commit_hlc,
        published_at: epoch_record.committed_at,
        metadata: %{
          "tenant_ref" => epoch_record.tenant_ref,
          "cause" => epoch_record.cause,
          "trace_id" => epoch_record.trace_id,
          "epoch" => epoch_record.epoch,
          "new_epoch" => epoch_record.epoch,
          "source_node_ref" => epoch_record.source_node_ref,
          "commit_lsn" => epoch_record.commit_lsn,
          "commit_hlc" => epoch_record.commit_hlc
        }
      })

    case ClusterInvalidationPublisher.publish(message) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback({:cluster_invalidation_publish_failed, reason})
    end
  end

  defp current_epoch_in_transaction(tenant_ref) do
    AccessGraphEpochRecord
    |> where([epoch], epoch.tenant_ref == ^tenant_ref)
    |> select([epoch], max(epoch.epoch))
    |> Repo.one()
    |> case do
      nil -> 0
      epoch -> epoch
    end
  end

  defp insert_edge!(%Edge{} = edge) do
    %AccessGraphEdgeRecord{}
    |> AccessGraphEdgeRecord.changeset(to_record_attrs(edge))
    |> Repo.insert!()
    |> to_edge()
  end

  defp revoke_edge_record!(nil, _revoking_authority_ref, _opts) do
    Repo.rollback(:unknown_access_graph_edge)
  end

  defp revoke_edge_record!(
         %AccessGraphEdgeRecord{epoch_end: epoch_end},
         _revoking_authority_ref,
         _opts
       )
       when not is_nil(epoch_end) do
    Repo.rollback(:access_graph_edge_already_revoked)
  end

  defp revoke_edge_record!(%AccessGraphEdgeRecord{} = record, revoking_authority_ref, opts) do
    epoch_record = allocate_epoch!(record.tenant_ref, opts)
    revoking = normalize_revoking_authority!(revoking_authority_ref)

    record
    |> AccessGraphEdgeRecord.changeset(%{
      epoch_end: epoch_record.epoch,
      revoking_authority_ref: GovernanceRef.dump(revoking)
    })
    |> Repo.update!()
    |> to_edge()
    |> tap(fn _edge -> publish_graph_invalidation!(epoch_record) end)
  end

  defp revoke_edge_records!(tenant_ref, [], _revoking_authority_ref, _opts) do
    %{epoch: current_epoch_in_transaction(tenant_ref), revoked_edges: []}
  end

  defp revoke_edge_records!(tenant_ref, records, revoking_authority_ref, opts) do
    epoch_record = allocate_epoch!(tenant_ref, opts)
    revoking = normalize_revoking_authority!(revoking_authority_ref)

    revoked_edges =
      Enum.map(records, fn record ->
        record
        |> AccessGraphEdgeRecord.changeset(%{
          epoch_end: epoch_record.epoch,
          revoking_authority_ref: GovernanceRef.dump(revoking)
        })
        |> Repo.update!()
        |> to_edge()
      end)

    publish_graph_invalidation!(epoch_record)
    %{epoch: epoch_record.epoch, revoked_edges: revoked_edges}
  end

  defp active_tails(tenant_ref, edge_type, head_ref, epoch) do
    tenant_ref
    |> active_edges(edge_type, head_ref, epoch)
    |> Enum.map(& &1.tail_ref)
    |> MapSet.new()
  end

  defp active_edges(tenant_ref, epoch) do
    AccessGraphEdgeRecord
    |> where([edge], edge.tenant_ref == ^tenant_ref)
    |> active_at_epoch(epoch)
    |> order_by([edge], asc: edge.epoch_start, asc: edge.edge_id)
    |> Repo.all()
    |> Enum.map(&to_edge/1)
  end

  defp active_edges(tenant_ref, edge_type, head_ref, epoch) do
    edge_type = Atom.to_string(edge_type)

    AccessGraphEdgeRecord
    |> where(
      [edge],
      edge.tenant_ref == ^tenant_ref and edge.edge_type == ^edge_type and
        edge.head_ref == ^head_ref
    )
    |> active_at_epoch(epoch)
    |> order_by([edge], asc: edge.epoch_start, asc: edge.edge_id)
    |> Repo.all()
    |> Enum.map(&to_edge/1)
  end

  defp active_at_epoch(query, epoch) do
    where(
      query,
      [edge],
      edge.epoch_start <= ^epoch and (is_nil(edge.epoch_end) or edge.epoch_end > ^epoch)
    )
  end

  defp maybe_filter_epoch(query, nil), do: query

  defp maybe_filter_epoch(query, epoch) when is_integer(epoch),
    do: where(query, [row], row.epoch == ^epoch)

  defp maybe_filter_source_node(query, nil), do: query

  defp maybe_filter_source_node(query, source_node_ref) when is_binary(source_node_ref) do
    where(query, [row], row.source_node_ref == ^source_node_ref)
  end

  defp order_by_commit(query) do
    order_by(query, [epoch],
      asc: fragment("(?->>'w')::bigint", epoch.commit_hlc),
      asc: fragment("(?->>'l')::bigint", epoch.commit_hlc),
      asc: epoch.source_node_ref,
      asc: epoch.commit_lsn,
      asc: epoch.tenant_ref,
      asc: epoch.epoch
    )
  end

  defp to_epoch_event(%AccessGraphEpochRecord{} = record) do
    %{
      tenant_ref: record.tenant_ref,
      epoch: record.epoch,
      committed_at: record.committed_at,
      source_node_ref: record.source_node_ref,
      commit_lsn: record.commit_lsn,
      commit_hlc: record.commit_hlc,
      cause: record.cause,
      trace_id: record.trace_id,
      metadata: record.metadata || %{}
    }
  end

  defp to_record_attrs(%Edge{} = edge) do
    %{
      edge_id: edge.edge_id,
      edge_type: Atom.to_string(edge.edge_type),
      head_ref: edge.head_ref,
      tail_ref: edge.tail_ref,
      tenant_ref: edge.tenant_ref,
      source_node_ref: edge.source_node_ref,
      epoch_start: edge.epoch_start,
      epoch_end: edge.epoch_end,
      granting_authority_ref:
        edge.granting_authority_ref |> GovernanceRef.dump() |> Contracts.dump_json_safe!(),
      revoking_authority_ref:
        edge.revoking_authority_ref
        |> maybe_dump_governance()
        |> Contracts.dump_json_safe!(),
      evidence_refs:
        edge.evidence_refs
        |> Enum.map(&Contracts.dump_json_safe!/1),
      policy_refs: edge.policy_refs,
      metadata: Contracts.dump_json_safe!(edge.metadata)
    }
  end

  defp to_edge(%AccessGraphEdgeRecord{} = record) do
    Edge.new!(%{
      edge_id: record.edge_id,
      edge_type: record.edge_type,
      head_ref: record.head_ref,
      tail_ref: record.tail_ref,
      tenant_ref: record.tenant_ref,
      source_node_ref: record.source_node_ref,
      epoch_start: record.epoch_start,
      epoch_end: record.epoch_end,
      granting_authority_ref: record.granting_authority_ref,
      revoking_authority_ref: record.revoking_authority_ref,
      evidence_refs: record.evidence_refs || [],
      policy_refs: record.policy_refs || [],
      metadata: record.metadata || %{}
    })
  end

  defp normalize_revoking_authority!(%GovernanceRef{} = ref), do: ref

  defp normalize_revoking_authority!(ref) when is_map(ref) or is_list(ref),
    do: GovernanceRef.new!(ref)

  defp maybe_dump_governance(nil), do: nil
  defp maybe_dump_governance(%GovernanceRef{} = ref), do: GovernanceRef.dump(ref)

  defp snapshot_from_epoch_record(tenant_ref, nil) do
    SnapshotContext.new!(%{
      tenant_ref: tenant_ref,
      snapshot_epoch: 0,
      pinned_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    })
  end

  defp snapshot_from_epoch_record(tenant_ref, %AccessGraphEpochRecord{} = epoch_record) do
    SnapshotContext.new!(%{
      tenant_ref: tenant_ref,
      snapshot_epoch: epoch_record.epoch,
      pinned_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      source_node_ref: epoch_record.source_node_ref,
      commit_lsn: epoch_record.commit_lsn,
      commit_hlc: epoch_record.commit_hlc
    })
  end

  defp emit_snapshot_pin_telemetry(%SnapshotContext{} = snapshot, status) do
    :telemetry.execute(
      [:memsim, :recall, :snapshot_pin, :latency],
      %{duration: snapshot.latency_us},
      %{
        tenant_ref: snapshot.tenant_ref,
        snapshot_epoch: snapshot.snapshot_epoch,
        status: status
      }
    )
  end

  defp elapsed_us(started), do: System.monotonic_time(:microsecond) - started

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end
