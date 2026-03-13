defmodule Jido.Integration.V2.StorePostgres.Schemas.CredentialRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "credentials" do
    field(:connection_id, :string)
    field(:subject, :string)
    field(:auth_type, :string)
    field(:scopes, {:array, :string}, default: [])
    field(:lease_fields, {:array, :string}, default: [])
    field(:secret_envelope, :map)
    field(:expires_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :connection_id,
      :subject,
      :auth_type,
      :scopes,
      :lease_fields,
      :secret_envelope,
      :expires_at,
      :revoked_at,
      :metadata,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :id,
      :connection_id,
      :subject,
      :auth_type,
      :secret_envelope,
      :inserted_at,
      :updated_at
    ])
  end
end
