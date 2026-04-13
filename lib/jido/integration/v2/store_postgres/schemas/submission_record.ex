defmodule Jido.Integration.V2.StorePostgres.Schemas.SubmissionRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:submission_key, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "submission_records" do
    field(:identity_checksum, :string)
    field(:status, :string)
    field(:acceptance_json, :map)
    field(:rejection_json, :map)

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :submission_key,
      :identity_checksum,
      :status,
      :acceptance_json,
      :rejection_json,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([:submission_key, :identity_checksum, :status])
    |> unique_constraint(:submission_key, name: :submission_records_pkey)
  end
end
