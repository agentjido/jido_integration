defmodule Jido.Integration.V2.StorePostgres.Schemas.AttemptRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:attempt_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "run_attempts" do
    field(:run_id, :string)
    field(:attempt, :integer)
    field(:aggregator_id, :string)
    field(:aggregator_epoch, :integer)
    field(:runtime_class, Ecto.Enum, values: [:direct, :session, :stream])
    field(:status, Ecto.Enum, values: [:accepted, :running, :completed, :failed])
    field(:credential_lease_id, :string)
    field(:target_id, :string)
    field(:runtime_ref_id, :string)
    field(:output, :map)

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :attempt_id,
      :run_id,
      :attempt,
      :aggregator_id,
      :aggregator_epoch,
      :runtime_class,
      :status,
      :credential_lease_id,
      :target_id,
      :runtime_ref_id,
      :output,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :attempt_id,
      :run_id,
      :attempt,
      :aggregator_id,
      :aggregator_epoch,
      :runtime_class,
      :status,
      :inserted_at,
      :updated_at
    ])
  end
end
