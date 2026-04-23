defmodule Jido.Integration.V2.StorePostgres.Schemas.AccessGraphEdgeRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:edge_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "access_graph_edges" do
    field(:edge_type, :string)
    field(:head_ref, :string)
    field(:tail_ref, :string)
    field(:tenant_ref, :string)
    field(:epoch_start, :integer)
    field(:epoch_end, :integer)
    field(:granting_authority_ref, :map)
    field(:revoking_authority_ref, :map)
    field(:evidence_refs, {:array, :map}, default: [])
    field(:policy_refs, {:array, :string}, default: [])
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :edge_id,
      :edge_type,
      :head_ref,
      :tail_ref,
      :tenant_ref,
      :epoch_start,
      :epoch_end,
      :granting_authority_ref,
      :revoking_authority_ref,
      :evidence_refs,
      :policy_refs,
      :metadata,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :edge_id,
      :edge_type,
      :head_ref,
      :tail_ref,
      :tenant_ref,
      :epoch_start,
      :granting_authority_ref
    ])
    |> unique_constraint(:edge_id, name: :access_graph_edges_pkey)
    |> check_constraint(:edge_type, name: :access_graph_edges_edge_type_check)
    |> check_constraint(:epoch_start, name: :access_graph_edges_epoch_start_positive_check)
    |> check_constraint(:epoch_end, name: :access_graph_edges_epoch_end_after_start_check)
    |> check_constraint(:revoking_authority_ref,
      name: :access_graph_edges_revocation_authority_check
    )
  end
end
