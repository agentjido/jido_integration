defmodule Jido.Integration.V2.StorePostgres.MemoryTierStore do
  @moduledoc """
  Canonical Postgres store for the three governed-memory physical tiers.
  """

  import Ecto.Query

  alias Jido.Integration.V2.ClockOrdering.HLC
  alias Jido.Integration.V2.ClusterInvalidation
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.MemoryFragment
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.ClusterInvalidationPublisher
  alias Jido.Integration.V2.StorePostgres.Repo

  alias Jido.Integration.V2.StorePostgres.Schemas.{
    MemoryGovernedRecord,
    MemoryInvalidationRecord,
    MemoryPrivateRecord,
    MemorySharedRecord
  }

  @spec insert_private_fragment(map() | keyword() | MemoryFragment.t()) ::
          {:ok, MemoryFragment.t()} | {:error, term()}
  def insert_private_fragment(attrs) do
    attrs
    |> build_fragment!(:private)
    |> insert_fragment(MemoryPrivateRecord)
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec insert_shared_fragment(map() | keyword() | MemoryFragment.t()) ::
          {:ok, MemoryFragment.t()} | {:error, term()}
  def insert_shared_fragment(attrs) do
    attrs
    |> build_fragment!(:shared)
    |> insert_fragment(MemorySharedRecord)
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec insert_governed_fragment(map() | keyword() | MemoryFragment.t()) ::
          {:ok, MemoryFragment.t()} | {:error, term()}
  def insert_governed_fragment(attrs) do
    attrs
    |> build_fragment!(:governed)
    |> insert_fragment(MemoryGovernedRecord)
  rescue
    error in ArgumentError -> {:error, error}
  end

  @type invalidation :: %{
          invalidation_id: String.t(),
          tenant_ref: String.t(),
          fragment_id: String.t(),
          tier: String.t(),
          effective_at: DateTime.t(),
          effective_at_epoch: pos_integer(),
          source_node_ref: String.t(),
          commit_lsn: String.t(),
          commit_hlc: map(),
          invalidate_policy_ref: String.t(),
          authority_ref: map(),
          evidence_refs: [map()],
          reason: String.t(),
          metadata: map()
        }

  @spec private_fragments(String.t(), String.t(), keyword()) :: [MemoryFragment.t()]
  def private_fragments(tenant_ref, user_ref, opts \\ [])
      when is_binary(tenant_ref) and is_binary(user_ref) and is_list(opts) do
    StorePostgres.assert_started!()

    MemoryPrivateRecord
    |> where([fragment], fragment.tenant_ref == ^tenant_ref and fragment.user_ref == ^user_ref)
    |> order_by([fragment], asc: fragment.inserted_at, asc: fragment.fragment_id)
    |> Repo.all()
    |> filter_snapshot_visible(opts)
    |> Enum.map(&to_fragment/1)
  end

  @spec shared_fragments(String.t(), String.t(), keyword()) :: [MemoryFragment.t()]
  def shared_fragments(tenant_ref, scope_ref, opts \\ [])
      when is_binary(tenant_ref) and is_binary(scope_ref) and is_list(opts) do
    StorePostgres.assert_started!()

    MemorySharedRecord
    |> where([fragment], fragment.tenant_ref == ^tenant_ref and fragment.scope_ref == ^scope_ref)
    |> order_by([fragment], asc: fragment.inserted_at, asc: fragment.fragment_id)
    |> Repo.all()
    |> filter_snapshot_visible(opts)
    |> Enum.map(&to_fragment/1)
  end

  @spec governed_fragments(String.t(), String.t(), keyword()) :: [MemoryFragment.t()]
  def governed_fragments(tenant_ref, installation_ref, opts \\ [])
      when is_binary(tenant_ref) and is_binary(installation_ref) and is_list(opts) do
    StorePostgres.assert_started!()

    MemoryGovernedRecord
    |> where(
      [fragment],
      fragment.tenant_ref == ^tenant_ref and fragment.installation_ref == ^installation_ref
    )
    |> order_by([fragment], asc: fragment.inserted_at, asc: fragment.fragment_id)
    |> Repo.all()
    |> filter_snapshot_visible(opts)
    |> Enum.map(&to_fragment/1)
  end

  @spec nearest_private_fragments(String.t(), String.t(), [number()], keyword()) ::
          [MemoryFragment.t()]
  def nearest_private_fragments(tenant_ref, user_ref, query_embedding, opts \\ [])
      when is_binary(tenant_ref) and is_binary(user_ref) and is_list(query_embedding) do
    limit = Keyword.get(opts, :limit, 10)
    normalized_query = normalize_query_embedding!(query_embedding)

    tenant_ref
    |> private_records(user_ref)
    |> Enum.filter(&same_dimension?(&1.embedding, normalized_query))
    |> Enum.sort_by(&squared_distance(&1.embedding, normalized_query))
    |> Enum.take(limit)
    |> Enum.map(&to_fragment/1)
  end

  @spec insert_invalidation(map() | keyword()) :: {:ok, invalidation()} | {:error, term()}
  def insert_invalidation(attrs) when is_map(attrs) or is_list(attrs) do
    StorePostgres.assert_started!()

    Repo.transaction(fn ->
      attrs =
        attrs
        |> normalize_invalidation_attrs!()
        |> Map.put_new(:commit_lsn, current_wal_lsn!())

      record =
        %MemoryInvalidationRecord{}
        |> MemoryInvalidationRecord.changeset(attrs)
        |> Repo.insert!()

      invalidation = to_invalidation(record)
      publish_memory_invalidations!(invalidation)
      invalidation
    end)
    |> unwrap_transaction()
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec fragment_invalidated_at_epoch?(String.t(), String.t(), pos_integer()) :: boolean()
  def fragment_invalidated_at_epoch?(tenant_ref, fragment_id, snapshot_epoch)
      when is_binary(tenant_ref) and is_binary(fragment_id) and is_integer(snapshot_epoch) do
    StorePostgres.assert_started!()

    MemoryInvalidationRecord
    |> where(
      [invalidation],
      invalidation.tenant_ref == ^tenant_ref and invalidation.fragment_id == ^fragment_id and
        invalidation.effective_at_epoch <= ^snapshot_epoch
    )
    |> limit(1)
    |> Repo.exists?()
  end

  defp insert_fragment(%MemoryFragment{tier: :private} = fragment, MemoryPrivateRecord) do
    StorePostgres.assert_started!()

    %MemoryPrivateRecord{}
    |> MemoryPrivateRecord.changeset(to_record_attrs(fragment))
    |> Repo.insert(returning: true)
    |> case do
      {:ok, record} -> {:ok, to_fragment(record)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp insert_fragment(%MemoryFragment{tier: :shared} = fragment, MemorySharedRecord) do
    StorePostgres.assert_started!()

    %MemorySharedRecord{}
    |> MemorySharedRecord.changeset(to_record_attrs(fragment))
    |> Repo.insert(returning: true)
    |> case do
      {:ok, record} -> {:ok, to_fragment(record)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp insert_fragment(%MemoryFragment{tier: :governed} = fragment, MemoryGovernedRecord) do
    StorePostgres.assert_started!()

    %MemoryGovernedRecord{}
    |> MemoryGovernedRecord.changeset(to_record_attrs(fragment))
    |> Repo.insert(returning: true)
    |> case do
      {:ok, record} -> {:ok, to_fragment(record)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp build_fragment!(%MemoryFragment{tier: tier} = fragment, expected_tier)
       when tier == expected_tier,
       do: MemoryFragment.new!(fragment)

  defp build_fragment!(%MemoryFragment{tier: tier}, expected_tier) do
    raise ArgumentError, "memory fragment tier #{inspect(tier)} does not match #{expected_tier}"
  end

  defp build_fragment!(attrs, expected_tier) when is_map(attrs) or is_list(attrs) do
    attrs
    |> Map.new()
    |> Map.put(:tier, expected_tier)
    |> MemoryFragment.new!()
  end

  defp private_records(tenant_ref, user_ref) do
    StorePostgres.assert_started!()

    MemoryPrivateRecord
    |> where([fragment], fragment.tenant_ref == ^tenant_ref and fragment.user_ref == ^user_ref)
    |> Repo.all()
  end

  defp filter_snapshot_visible(records, opts) do
    case Keyword.get(opts, :snapshot_epoch) do
      nil ->
        records

      snapshot_epoch when is_integer(snapshot_epoch) and snapshot_epoch > 0 ->
        Enum.reject(records, fn record ->
          fragment_invalidated_at_epoch?(record.tenant_ref, record.fragment_id, snapshot_epoch)
        end)

      snapshot_epoch ->
        raise ArgumentError,
              "memory_tier_store.snapshot_epoch must be a positive integer, got: #{inspect(snapshot_epoch)}"
    end
  end

  defp normalize_invalidation_attrs!(attrs) do
    attrs = Map.new(attrs)

    source_node_ref =
      required_string(attrs, :source_node_ref, "memory_invalidation.source_node_ref")

    attrs
    |> Map.put_new(:invalidation_id, Contracts.next_id("memory_invalidation"))
    |> Map.update(:tier, nil, &normalize_tier!/1)
    |> Map.update(:effective_at, Contracts.now(), &normalize_datetime!/1)
    |> Map.update(
      :effective_at_epoch,
      nil,
      &positive_integer!(&1, "memory_invalidation.effective_at_epoch")
    )
    |> Map.put(:source_node_ref, source_node_ref)
    |> Map.put_new(:commit_hlc, HLC.local_event(nil, source_node_ref) |> HLC.dump())
    |> Map.update(:commit_hlc, nil, &HLC.dump/1)
    |> Map.update(:authority_ref, nil, &Contracts.dump_json_safe!/1)
    |> Map.update(:evidence_refs, [], fn evidence_refs ->
      Enum.map(evidence_refs, &Contracts.dump_json_safe!/1)
    end)
    |> Map.update(:metadata, %{}, &Contracts.dump_json_safe!/1)
  end

  defp publish_memory_invalidations!(invalidation) do
    messages = [
      memory_invalidation_message(invalidation, :fragment),
      memory_invalidation_message(invalidation, :invalidation)
    ]

    case ClusterInvalidationPublisher.publish_all(messages) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback({:cluster_invalidation_publish_failed, reason})
    end
  end

  defp memory_invalidation_message(invalidation, :fragment) do
    build_memory_invalidation_message(
      invalidation,
      ClusterInvalidation.fragment_topic!(invalidation.tenant_ref, invalidation.fragment_id)
    )
  end

  defp memory_invalidation_message(invalidation, :invalidation) do
    build_memory_invalidation_message(
      invalidation,
      ClusterInvalidation.invalidation_topic!(
        invalidation.tenant_ref,
        invalidation.invalidation_id
      )
    )
  end

  defp build_memory_invalidation_message(invalidation, topic) do
    ClusterInvalidation.new!(%{
      invalidation_id: invalidation.invalidation_id,
      tenant_ref: invalidation.tenant_ref,
      topic: topic,
      source_node_ref: invalidation.source_node_ref,
      commit_lsn: invalidation.commit_lsn,
      commit_hlc: invalidation.commit_hlc,
      published_at: invalidation.effective_at,
      metadata: %{
        fragment_id: invalidation.fragment_id,
        tier: invalidation.tier,
        effective_at_epoch: invalidation.effective_at_epoch,
        reason: invalidation.reason
      }
    })
  end

  defp to_invalidation(%MemoryInvalidationRecord{} = record) do
    %{
      invalidation_id: record.invalidation_id,
      tenant_ref: record.tenant_ref,
      fragment_id: record.fragment_id,
      tier: record.tier,
      effective_at: record.effective_at,
      effective_at_epoch: record.effective_at_epoch,
      source_node_ref: record.source_node_ref,
      commit_lsn: record.commit_lsn,
      commit_hlc: record.commit_hlc,
      invalidate_policy_ref: record.invalidate_policy_ref,
      authority_ref: record.authority_ref,
      evidence_refs: record.evidence_refs || [],
      reason: record.reason,
      metadata: record.metadata || %{}
    }
  end

  defp current_wal_lsn! do
    %{rows: [[commit_lsn]]} = Repo.query!("SELECT pg_current_wal_lsn()::text", [])
    commit_lsn
  end

  defp normalize_tier!(tier) when tier in [:private, :shared, :governed], do: Atom.to_string(tier)
  defp normalize_tier!(tier) when tier in ["private", "shared", "governed"], do: tier

  defp normalize_tier!(tier) do
    raise ArgumentError,
          "memory_invalidation.tier must be private, shared, or governed, got: #{inspect(tier)}"
  end

  defp normalize_datetime!(%DateTime{} = value), do: value

  defp normalize_datetime!(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> raise ArgumentError, "memory_invalidation.effective_at must be a DateTime"
    end
  end

  defp normalize_datetime!(value) do
    raise ArgumentError,
          "memory_invalidation.effective_at must be a DateTime, got: #{inspect(value)}"
  end

  defp positive_integer!(value, _field) when is_integer(value) and value > 0, do: value

  defp positive_integer!(value, field) do
    raise ArgumentError, "#{field} must be a positive integer, got: #{inspect(value)}"
  end

  defp required_string(attrs, key, field) do
    attrs
    |> Contracts.get(key)
    |> Contracts.validate_non_empty_string!(field)
  end

  defp unwrap_transaction({:ok, value}), do: {:ok, value}
  defp unwrap_transaction({:error, reason}), do: {:error, reason}

  defp normalize_query_embedding!(values) do
    Enum.map(values, fn
      value when is_number(value) -> value * 1.0
      value -> raise ArgumentError, "query embedding must contain numbers, got: #{inspect(value)}"
    end)
  end

  defp same_dimension?(embedding, query_embedding) when is_list(embedding),
    do: length(embedding) == length(query_embedding)

  defp same_dimension?(_embedding, _query_embedding), do: false

  defp squared_distance(embedding, query_embedding) do
    embedding
    |> Enum.zip(query_embedding)
    |> Enum.reduce(0.0, fn {left, right}, acc -> acc + :math.pow(left - right, 2) end)
  end

  defp to_record_attrs(%MemoryFragment{} = fragment) do
    fragment
    |> MemoryFragment.dump()
    |> Map.merge(%{
      evidence_refs:
        fragment.evidence_refs
        |> Enum.map(&Contracts.dump_json_safe!/1),
      governance_refs:
        fragment.governance_refs
        |> Enum.map(&Contracts.dump_json_safe!/1),
      content_ref: Contracts.dump_json_safe!(fragment.content_ref),
      redaction_summary: Contracts.dump_json_safe!(fragment.redaction_summary),
      transform_pipeline:
        fragment.transform_pipeline
        |> Enum.map(&Contracts.dump_json_safe!/1),
      rebuild_spec: maybe_dump_json_safe(fragment.rebuild_spec),
      metadata: Contracts.dump_json_safe!(fragment.metadata)
    })
  end

  defp to_fragment(%MemoryPrivateRecord{} = record) do
    record
    |> common_fragment_attrs(:private)
    |> Map.merge(%{
      creating_user_ref: record.creating_user_ref,
      user_ref: record.user_ref
    })
    |> MemoryFragment.new!()
  end

  defp to_fragment(%MemorySharedRecord{} = record) do
    record
    |> common_fragment_attrs(:shared)
    |> Map.merge(%{
      scope_ref: record.scope_ref,
      share_up_policy_ref: record.share_up_policy_ref,
      transform_pipeline: record.transform_pipeline || [],
      non_identity_transform_count: record.non_identity_transform_count || 0
    })
    |> MemoryFragment.new!()
  end

  defp to_fragment(%MemoryGovernedRecord{} = record) do
    record
    |> common_fragment_attrs(:governed)
    |> Map.merge(%{
      installation_ref: record.installation_ref,
      promotion_decision_ref: record.promotion_decision_ref,
      promotion_policy_ref: record.promotion_policy_ref,
      rebuild_spec: record.rebuild_spec,
      derived_state_attachment_ref: record.derived_state_attachment_ref
    })
    |> MemoryFragment.new!()
  end

  defp common_fragment_attrs(record, tier) do
    %{
      fragment_id: record.fragment_id,
      tenant_ref: record.tenant_ref,
      source_node_ref: record.source_node_ref,
      tier: tier,
      t_epoch: record.t_epoch,
      source_agents: list_or_empty(record.source_agents),
      source_resources: list_or_empty(record.source_resources),
      source_scopes: list_or_empty(record.source_scopes),
      access_agents: list_or_empty(record.access_agents),
      access_resources: list_or_empty(record.access_resources),
      access_scopes: list_or_empty(record.access_scopes),
      access_projection_hash: record.access_projection_hash,
      applied_policies: list_or_empty(record.applied_policies),
      evidence_refs: list_or_empty(record.evidence_refs),
      governance_refs: list_or_empty(record.governance_refs),
      parent_fragment_id: record.parent_fragment_id,
      content_hash: record.content_hash,
      content_ref: record.content_ref,
      schema_ref: record.schema_ref,
      embedding: record.embedding,
      embedding_model_ref: record.embedding_model_ref,
      embedding_dimension: record.embedding_dimension,
      redaction_summary: map_or_empty(record.redaction_summary),
      confidence: record.confidence,
      retention_class: record.retention_class,
      expires_at: record.expires_at,
      metadata: map_or_empty(record.metadata)
    }
  end

  defp list_or_empty(nil), do: []
  defp list_or_empty(value), do: value

  defp map_or_empty(nil), do: %{}
  defp map_or_empty(value), do: value

  defp maybe_dump_json_safe(nil), do: nil
  defp maybe_dump_json_safe(value), do: Contracts.dump_json_safe!(value)
end
