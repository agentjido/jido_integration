defmodule Jido.Integration.V2.StorePostgres.Schemas.ClaimCheckReferenceRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec]

  schema "claim_check_references" do
    field(:store, :string)
    field(:key, :string)
    field(:ledger_kind, :string)
    field(:ledger_id, :string)
    field(:payload_field, :string)
    field(:run_id, :string)
    field(:attempt_id, :string)
    field(:event_id, :string)
    field(:trace_id, :string)

    timestamps(updated_at: false)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :store,
      :key,
      :ledger_kind,
      :ledger_id,
      :payload_field,
      :run_id,
      :attempt_id,
      :event_id,
      :trace_id,
      :inserted_at
    ])
    |> validate_required([
      :store,
      :key,
      :ledger_kind,
      :ledger_id,
      :payload_field,
      :inserted_at
    ])
    |> unique_constraint(:ledger_id, name: :claim_check_references_ledger_identity_index)
  end
end
