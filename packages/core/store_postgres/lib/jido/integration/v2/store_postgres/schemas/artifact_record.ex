defmodule Jido.Integration.V2.StorePostgres.Schemas.ArtifactRecord do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:artifact_id, :string, autogenerate: false}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "artifact_refs" do
    field(:run_id, :string)
    field(:attempt_id, :string)

    field(:artifact_type, Ecto.Enum,
      values: [:event_log, :stdout, :stderr, :diff, :tarball, :tool_output, :log, :custom]
    )

    field(:transport_mode, Ecto.Enum, values: [:inline, :chunked, :object_store])
    field(:checksum, :string)
    field(:size_bytes, :integer)
    field(:payload_ref, :map)
    field(:retention_class, :string)
    field(:redaction_status, Ecto.Enum, values: [:clear, :redacted, :withheld])
    field(:metadata, :map, default: %{})

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :artifact_id,
      :run_id,
      :attempt_id,
      :artifact_type,
      :transport_mode,
      :checksum,
      :size_bytes,
      :payload_ref,
      :retention_class,
      :redaction_status,
      :metadata,
      :inserted_at,
      :updated_at
    ])
    |> validate_required([
      :artifact_id,
      :run_id,
      :attempt_id,
      :artifact_type,
      :transport_mode,
      :checksum,
      :size_bytes,
      :payload_ref,
      :retention_class,
      :redaction_status
    ])
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:attempt_id)
  end
end
