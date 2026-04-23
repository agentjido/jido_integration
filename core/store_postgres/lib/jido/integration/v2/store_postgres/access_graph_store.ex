defmodule Jido.Integration.V2.StorePostgres.AccessGraphStore do
  @moduledoc """
  Canonical Postgres access graph store.
  """

  import Ecto.Query

  alias Jido.Integration.V2.AccessGraph
  alias Jido.Integration.V2.AccessGraph.Edge
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.StorePostgres
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
      epoch = allocate_epoch!(tenant_ref, opts)

      edges =
        Enum.map(edge_attrs, fn attrs ->
          attrs
          |> Map.new()
          |> Map.put(:tenant_ref, tenant_ref)
          |> Map.put(:epoch_start, epoch)
          |> Map.put_new(:edge_id, Contracts.next_id("access_graph_edge"))
          |> Edge.new!()
          |> insert_edge!()
        end)

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

      case edge_record do
        nil ->
          Repo.rollback(:unknown_access_graph_edge)

        %AccessGraphEdgeRecord{epoch_end: epoch_end} when not is_nil(epoch_end) ->
          Repo.rollback(:access_graph_edge_already_revoked)

        %AccessGraphEdgeRecord{} = record ->
          epoch = allocate_epoch!(record.tenant_ref, opts)
          revoking = normalize_revoking_authority!(revoking_authority_ref)

          record
          |> AccessGraphEdgeRecord.changeset(%{
            epoch_end: epoch,
            revoking_authority_ref: GovernanceRef.dump(revoking)
          })
          |> Repo.update!()
          |> to_edge()
      end
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

  defp allocate_epoch!(tenant_ref, opts) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["access_graph:" <> tenant_ref])

    epoch = current_epoch_in_transaction(tenant_ref) + 1

    %AccessGraphEpochRecord{}
    |> AccessGraphEpochRecord.changeset(%{
      tenant_ref: tenant_ref,
      epoch: epoch,
      committed_at:
        Keyword.get(opts, :committed_at, DateTime.utc_now() |> DateTime.truncate(:microsecond)),
      cause: Keyword.get(opts, :cause, "graph_change"),
      trace_id: Keyword.get(opts, :trace_id),
      metadata: Keyword.get(opts, :metadata, %{})
    })
    |> Repo.insert!()

    epoch
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

  defp to_record_attrs(%Edge{} = edge) do
    %{
      edge_id: edge.edge_id,
      edge_type: Atom.to_string(edge.edge_type),
      head_ref: edge.head_ref,
      tail_ref: edge.tail_ref,
      tenant_ref: edge.tenant_ref,
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

  defp unwrap_transaction({:ok, result}), do: {:ok, result}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end
