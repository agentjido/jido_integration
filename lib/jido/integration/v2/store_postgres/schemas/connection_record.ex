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
    field(:profile_id, :string)
    field(:subject, :string)
    field(:state, :string)
    field(:credential_ref_id, :string)
    field(:current_credential_ref_id, :string)
    field(:current_credential_id, :string)
    field(:install_id, :string)
    field(:management_mode, :string)
    field(:secret_source, :string)
    field(:external_secret_ref, :map)
    field(:requested_scopes, {:array, :string}, default: [])
    field(:granted_scopes, {:array, :string}, default: [])
    field(:lease_fields, {:array, :string}, default: [])
    field(:token_expires_at, :utc_datetime_usec)
    field(:last_refresh_at, :utc_datetime_usec)
    field(:last_refresh_status, :string)
    field(:last_rotated_at, :utc_datetime_usec)
    field(:degraded_reason, :string)
    field(:reauth_required_reason, :string)
    field(:disabled_reason, :string)
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
      :profile_id,
      :subject,
      :state,
      :credential_ref_id,
      :current_credential_ref_id,
      :current_credential_id,
      :install_id,
      :management_mode,
      :secret_source,
      :external_secret_ref,
      :requested_scopes,
      :granted_scopes,
      :lease_fields,
      :token_expires_at,
      :last_refresh_at,
      :last_refresh_status,
      :last_rotated_at,
      :degraded_reason,
      :reauth_required_reason,
      :disabled_reason,
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
