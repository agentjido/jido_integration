defmodule Jido.Integration.V2.StorePostgres.Schemas.DedupeKeyRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "dedupe_keys" do
    field(:tenant_id, :string)
    field(:connector_id, :string)
    field(:trigger_id, :string)
    field(:dedupe_key, :string)
    field(:expires_at, :utc_datetime_usec)

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :tenant_id,
      :connector_id,
      :trigger_id,
      :dedupe_key,
      :expires_at,
      :inserted_at
    ])
    |> validate_required([:tenant_id, :connector_id, :trigger_id, :dedupe_key, :expires_at])
    |> unique_constraint(:dedupe_key, name: :dedupe_keys_scope_index)
  end
end
