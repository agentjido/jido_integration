defmodule Jido.Integration.V2.StorePostgres.Schemas.InstallRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:install_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "install_sessions" do
    field(:connection_id, :string)
    field(:tenant_id, :string)
    field(:connector_id, :string)
    field(:actor_id, :string)
    field(:auth_type, :string)
    field(:profile_id, :string)
    field(:subject, :string)
    field(:state, :string)
    field(:flow_kind, :string)
    field(:callback_token, :string)
    field(:state_token, :string)
    field(:pkce_verifier_digest, :string)
    field(:callback_uri, :string)
    field(:requested_scopes, {:array, :string}, default: [])
    field(:granted_scopes, {:array, :string}, default: [])
    field(:expires_at, :utc_datetime_usec)
    field(:callback_received_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)
    field(:cancelled_at, :utc_datetime_usec)
    field(:failure_reason, :string)
    field(:reauth_of_connection_id, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :install_id,
      :connection_id,
      :tenant_id,
      :connector_id,
      :actor_id,
      :auth_type,
      :profile_id,
      :subject,
      :state,
      :flow_kind,
      :callback_token,
      :state_token,
      :pkce_verifier_digest,
      :callback_uri,
      :requested_scopes,
      :granted_scopes,
      :expires_at,
      :callback_received_at,
      :completed_at,
      :cancelled_at,
      :failure_reason,
      :reauth_of_connection_id,
      :metadata,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :install_id,
      :connection_id,
      :tenant_id,
      :connector_id,
      :actor_id,
      :auth_type,
      :profile_id,
      :subject,
      :state,
      :callback_token,
      :expires_at,
      :inserted_at,
      :updated_at
    ])
  end
end
