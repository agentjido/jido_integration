defmodule Jido.Integration.V2.StorePostgres.Schemas.MemoryInvalidationRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:invalidation_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "memory_invalidations" do
    field(:tenant_ref, :string)
    field(:fragment_id, :string)
    field(:tier, :string)
    field(:effective_at, :utc_datetime_usec)
    field(:effective_at_epoch, :integer)
    field(:source_node_ref, :string)
    field(:commit_lsn, :string)
    field(:commit_hlc, :map)
    field(:invalidate_policy_ref, :string)
    field(:authority_ref, :map)
    field(:evidence_refs, {:array, :map}, default: [])
    field(:reason, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :invalidation_id,
      :tenant_ref,
      :fragment_id,
      :tier,
      :effective_at,
      :effective_at_epoch,
      :source_node_ref,
      :commit_lsn,
      :commit_hlc,
      :invalidate_policy_ref,
      :authority_ref,
      :evidence_refs,
      :reason,
      :metadata
    ])
    |> validate_required([
      :invalidation_id,
      :tenant_ref,
      :fragment_id,
      :tier,
      :effective_at,
      :effective_at_epoch,
      :source_node_ref,
      :commit_lsn,
      :commit_hlc,
      :invalidate_policy_ref,
      :authority_ref,
      :evidence_refs,
      :reason
    ])
    |> check_constraint(:source_node_ref,
      name: :memory_invalidations_source_node_ref_non_empty_check
    )
    |> check_constraint(:commit_lsn, name: :memory_invalidations_commit_lsn_non_empty_check)
    |> unique_constraint(:invalidation_id, name: :memory_invalidations_pkey)
  end
end
