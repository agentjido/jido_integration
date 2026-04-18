defmodule Jido.Integration.V2.StorePostgres.Schemas.ClaimCheckBlobRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]

  schema "claim_check_blobs" do
    field(:store, :string)
    field(:key, :string)
    field(:checksum, :string)
    field(:size_bytes, :integer)
    field(:content_type, :string)
    field(:redaction_class, :string)
    field(:status, Ecto.Enum, values: [:staged, :referenced, :swept, :deleted])
    field(:trace_id, :string)
    field(:payload_kind, :string)
    field(:staged_at, :utc_datetime_usec)
    field(:referenced_at, :utc_datetime_usec)
    field(:deleted_at, :utc_datetime_usec)

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :store,
      :key,
      :checksum,
      :size_bytes,
      :content_type,
      :redaction_class,
      :status,
      :trace_id,
      :payload_kind,
      :staged_at,
      :referenced_at,
      :deleted_at,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :store,
      :key,
      :checksum,
      :size_bytes,
      :content_type,
      :redaction_class,
      :status,
      :staged_at,
      :inserted_at,
      :updated_at
    ])
    |> unique_constraint(:key, name: :claim_check_blobs_store_key_index)
  end
end
