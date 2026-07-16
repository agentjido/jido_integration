defmodule Jido.Integration.V2.StorePostgres.Schemas.ManagedAccountRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:account_ref, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "managed_provider_accounts" do
    field(:provider_family, :string)
    field(:tenant_id, :string)
    field(:connection_id, :string)
    field(:endpoint_ref, :string)
    field(:quota_scope_ref, :string)
    field(:generation, :integer)
    field(:fence, :integer)
    field(:credential_handle_ref, :string)
    field(:secret_provider_ref, :string)
    field(:secret_binding_ref, :string)
    field(:state, Ecto.Enum, values: [:active, :revoked])
    field(:revoked_at, :utc_datetime_usec)
    field(:revocation_ref, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :account_ref,
      :provider_family,
      :tenant_id,
      :connection_id,
      :endpoint_ref,
      :quota_scope_ref,
      :generation,
      :fence,
      :credential_handle_ref,
      :secret_provider_ref,
      :secret_binding_ref,
      :state,
      :revoked_at,
      :revocation_ref,
      :metadata,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :account_ref,
      :provider_family,
      :tenant_id,
      :connection_id,
      :endpoint_ref,
      :quota_scope_ref,
      :generation,
      :fence,
      :credential_handle_ref,
      :secret_provider_ref,
      :secret_binding_ref,
      :state,
      :inserted_at,
      :updated_at
    ])
    |> validate_number(:generation, greater_than: 0)
    |> validate_number(:fence, greater_than_or_equal_to: 0)
    |> unique_constraint(:connection_id)
  end
end
