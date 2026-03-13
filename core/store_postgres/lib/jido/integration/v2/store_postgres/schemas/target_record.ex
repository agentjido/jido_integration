defmodule Jido.Integration.V2.StorePostgres.Schemas.TargetRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:target_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "target_descriptors" do
    field(:capability_id, :string)
    field(:runtime_class, Ecto.Enum, values: [:direct, :session, :stream])
    field(:version, :string)
    field(:features, :map, default: %{})
    field(:constraints, :map, default: %{})
    field(:health, Ecto.Enum, values: [:healthy, :degraded, :unavailable])
    field(:location, :map, default: %{})
    field(:extensions, :map, default: %{})

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :target_id,
      :capability_id,
      :runtime_class,
      :version,
      :features,
      :constraints,
      :health,
      :location,
      :extensions,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :target_id,
      :capability_id,
      :runtime_class,
      :version,
      :features,
      :constraints,
      :health,
      :location,
      :extensions
    ])
  end
end
