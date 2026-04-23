defmodule Jido.Integration.V2.StorePostgres.Schemas.AccessGraphEpochRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  schema "access_graph_epochs" do
    field(:tenant_ref, :string)
    field(:epoch, :integer)
    field(:committed_at, :utc_datetime_usec)
    field(:source_node_ref, :string)
    field(:commit_lsn, :string)
    field(:commit_hlc, :map)
    field(:cause, :string)
    field(:trace_id, :string)
    field(:metadata, :map, default: %{})

    timestamps(updated_at: false)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :tenant_ref,
      :epoch,
      :committed_at,
      :source_node_ref,
      :commit_lsn,
      :commit_hlc,
      :cause,
      :trace_id,
      :metadata,
      :inserted_at
    ])
    |> validate_required([
      :tenant_ref,
      :epoch,
      :committed_at,
      :source_node_ref,
      :commit_lsn,
      :commit_hlc,
      :cause
    ])
    |> unique_constraint(:tenant_ref, name: :access_graph_epochs_tenant_epoch_index)
    |> check_constraint(:epoch, name: :access_graph_epochs_epoch_positive_check)
    |> check_constraint(:source_node_ref,
      name: :access_graph_epochs_source_node_ref_non_empty_check
    )
    |> check_constraint(:commit_lsn, name: :access_graph_epochs_commit_lsn_non_empty_check)
  end
end
