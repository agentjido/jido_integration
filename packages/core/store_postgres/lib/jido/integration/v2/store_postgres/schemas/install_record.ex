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
    field(:subject, :string)
    field(:state, :string)
    field(:callback_token, :string)
    field(:requested_scopes, {:array, :string}, default: [])
    field(:granted_scopes, {:array, :string}, default: [])
    field(:expires_at, :utc_datetime_usec)
    field(:completed_at, :utc_datetime_usec)
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
      :subject,
      :state,
      :callback_token,
      :requested_scopes,
      :granted_scopes,
      :expires_at,
      :completed_at,
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
      :subject,
      :state,
      :callback_token,
      :expires_at,
      :inserted_at,
      :updated_at
    ])
  end
end
