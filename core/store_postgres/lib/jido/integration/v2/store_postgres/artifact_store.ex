defmodule Jido.Integration.V2.StorePostgres.ArtifactStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.ArtifactStore

  import Ecto.Query

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.ArtifactRecord
  alias Jido.Integration.V2.StorePostgres.Serialization

  @impl true
  def put_artifact_ref(%ArtifactRef{} = artifact_ref) do
    artifact_ref
    |> to_record_attrs()
    |> then(&ArtifactRecord.changeset(%ArtifactRecord{}, &1))
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:artifact_id, :inserted_at]},
      conflict_target: [:artifact_id]
    )
    |> case do
      {:ok, _record} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def fetch_artifact_ref(artifact_id) do
    case Repo.get(ArtifactRecord, artifact_id) do
      nil -> :error
      record -> {:ok, to_contract(record)}
    end
  end

  @impl true
  def list_artifact_refs(run_id) do
    from(artifact in ArtifactRecord,
      where: artifact.run_id == ^run_id,
      order_by: [asc: artifact.inserted_at, asc: artifact.artifact_id]
    )
    |> Repo.all()
    |> Enum.map(&to_contract/1)
  end

  def reset! do
    StorePostgres.ensure_started!()
    Repo.delete_all(ArtifactRecord)
    :ok
  end

  defp to_record_attrs(%ArtifactRef{} = artifact_ref) do
    %{
      artifact_id: artifact_ref.artifact_id,
      run_id: artifact_ref.run_id,
      attempt_id: artifact_ref.attempt_id,
      artifact_type: artifact_ref.artifact_type,
      transport_mode: artifact_ref.transport_mode,
      checksum: artifact_ref.checksum,
      size_bytes: artifact_ref.size_bytes,
      payload_ref: Serialization.dump(artifact_ref.payload_ref),
      retention_class: artifact_ref.retention_class,
      redaction_status: artifact_ref.redaction_status,
      metadata: Serialization.dump(artifact_ref.metadata)
    }
  end

  defp to_contract(record) do
    ArtifactRef.new!(%{
      artifact_id: record.artifact_id,
      run_id: record.run_id,
      attempt_id: record.attempt_id,
      artifact_type: record.artifact_type,
      transport_mode: record.transport_mode,
      checksum: record.checksum,
      size_bytes: record.size_bytes,
      payload_ref: Serialization.load(record.payload_ref),
      retention_class: record.retention_class,
      redaction_status: record.redaction_status,
      metadata: Serialization.load(record.metadata || %{})
    })
  end
end
