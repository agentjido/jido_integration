defmodule Jido.Integration.V2.StorePostgres.Schemas.ExpiredSubmissionRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "expired_submission_records" do
    field(:submission_key, :string)
    field(:tenant_id, :string)
    field(:submission_dedupe_key, :string)
    field(:identity_checksum, :string)
    field(:status, :string)
    field(:acceptance_json, :map)
    field(:rejection_json, :map)
    field(:last_seen_at, :utc_datetime_usec)
    field(:expired_at, :utc_datetime_usec)

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :submission_key,
      :tenant_id,
      :submission_dedupe_key,
      :identity_checksum,
      :status,
      :acceptance_json,
      :rejection_json,
      :last_seen_at,
      :expired_at,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :submission_key,
      :tenant_id,
      :submission_dedupe_key,
      :identity_checksum,
      :status,
      :last_seen_at,
      :expired_at
    ])
  end
end
