defmodule Jido.Integration.V2.StorePostgres.Schemas.CredentialRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "credentials" do
    field(:credential_ref_id, :string)
    field(:connection_id, :string)
    field(:profile_id, :string)
    field(:subject, :string)
    field(:auth_type, :string)
    field(:version, :integer, default: 1)
    field(:scopes, {:array, :string}, default: [])
    field(:lease_fields, {:array, :string}, default: [])
    field(:secret_envelope, :map)
    field(:expires_at, :utc_datetime_usec)
    field(:refresh_token_expires_at, :utc_datetime_usec)
    field(:source, :string)
    field(:source_ref, :map)
    field(:supersedes_credential_id, :string)
    field(:revoked_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :id,
      :credential_ref_id,
      :connection_id,
      :profile_id,
      :subject,
      :auth_type,
      :version,
      :scopes,
      :lease_fields,
      :secret_envelope,
      :expires_at,
      :refresh_token_expires_at,
      :source,
      :source_ref,
      :supersedes_credential_id,
      :revoked_at,
      :metadata,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :id,
      :credential_ref_id,
      :connection_id,
      :subject,
      :auth_type,
      :secret_envelope,
      :inserted_at,
      :updated_at
    ])
  end
end
