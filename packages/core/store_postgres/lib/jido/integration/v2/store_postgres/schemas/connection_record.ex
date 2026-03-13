defmodule Jido.Integration.V2.StorePostgres.Schemas.ConnectionRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:connection_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "connections" do
    field(:tenant_id, :string)
    field(:connector_id, :string)
    field(:auth_type, :string)
    field(:subject, :string)
    field(:state, :string)
    field(:credential_ref_id, :string)
    field(:install_id, :string)
    field(:requested_scopes, {:array, :string}, default: [])
    field(:granted_scopes, {:array, :string}, default: [])
    field(:lease_fields, {:array, :string}, default: [])
    field(:token_expires_at, :utc_datetime_usec)
    field(:last_rotated_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    field(:revocation_reason, :string)
    field(:actor_id, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :connection_id,
      :tenant_id,
      :connector_id,
      :auth_type,
      :subject,
      :state,
      :credential_ref_id,
      :install_id,
      :requested_scopes,
      :granted_scopes,
      :lease_fields,
      :token_expires_at,
      :last_rotated_at,
      :revoked_at,
      :revocation_reason,
      :actor_id,
      :metadata,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :connection_id,
      :tenant_id,
      :connector_id,
      :auth_type,
      :subject,
      :state,
      :inserted_at,
      :updated_at
    ])
  end
end
