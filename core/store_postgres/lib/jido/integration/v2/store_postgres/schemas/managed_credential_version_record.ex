defmodule Jido.Integration.V2.StorePostgres.Schemas.ManagedCredentialVersionRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  schema "managed_credential_versions" do
    field(:account_ref, :string, primary_key: true)
    field(:generation, :integer, primary_key: true)
    field(:credential_handle_ref, :string)
    field(:secret_provider_ref, :string)
    field(:secret_binding_ref, :string)
    field(:supersedes_generation, :integer)
    field(:superseded_at, :utc_datetime_usec)
    field(:revoked_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})
    field(:inserted_at, :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :account_ref,
      :generation,
      :credential_handle_ref,
      :secret_provider_ref,
      :secret_binding_ref,
      :supersedes_generation,
      :superseded_at,
      :revoked_at,
      :metadata,
      :inserted_at
    ])
    |> validate_required([
      :account_ref,
      :generation,
      :credential_handle_ref,
      :secret_provider_ref,
      :secret_binding_ref,
      :inserted_at
    ])
    |> validate_number(:generation, greater_than: 0)
    |> unique_constraint([:account_ref, :generation],
      name: :managed_credential_versions_pkey
    )
  end
end
