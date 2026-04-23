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
      :invalidate_policy_ref,
      :authority_ref,
      :evidence_refs,
      :reason
    ])
    |> unique_constraint(:invalidation_id, name: :memory_invalidations_pkey)
  end
end
