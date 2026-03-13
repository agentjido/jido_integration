defmodule Jido.Integration.V2.StorePostgres.Schemas.RunRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:run_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "runs" do
    field(:capability_id, :string)
    field(:runtime_class, Ecto.Enum, values: [:direct, :session, :stream])
    field(:status, Ecto.Enum, values: [:accepted, :running, :completed, :failed, :denied])
    field(:input, :map)
    field(:credential_ref, :map)
    field(:target_id, :string)
    field(:result, :map)
    field(:artifact_refs, {:array, :map}, default: [])

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :run_id,
      :capability_id,
      :runtime_class,
      :status,
      :input,
      :credential_ref,
      :target_id,
      :result,
      :artifact_refs,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :run_id,
      :capability_id,
      :runtime_class,
      :status,
      :input,
      :credential_ref,
      :inserted_at,
      :updated_at
    ])
  end
end
