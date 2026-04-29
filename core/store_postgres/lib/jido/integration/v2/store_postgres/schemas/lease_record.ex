defmodule Jido.Integration.V2.StorePostgres.Schemas.LeaseRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:lease_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "credential_leases" do
    field(:tenant_id, :string)
    field(:credential_ref_id, :string)
    field(:credential_id, :string)
    field(:connection_id, :string)
    field(:profile_id, :string)
    field(:subject, :string)
    field(:scopes, {:array, :string}, default: [])
    field(:payload_keys, {:array, :string}, default: [])
    field(:issued_at, :utc_datetime_usec)
    field(:expires_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    timestamps(updated_at: false)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :lease_id,
      :tenant_id,
      :credential_ref_id,
      :credential_id,
      :connection_id,
      :profile_id,
      :subject,
      :scopes,
      :payload_keys,
      :issued_at,
      :expires_at,
      :revoked_at,
      :metadata,
      :inserted_at
    ])
    |> validate_required([
      :lease_id,
      :tenant_id,
      :credential_ref_id,
      :credential_id,
      :connection_id,
      :subject,
      :payload_keys,
      :issued_at,
      :expires_at
    ])
  end
end
