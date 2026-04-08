defmodule Jido.Integration.V2.StorePostgres.RunStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.RunStore

  import Ecto.Query

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.AttemptRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.EventRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.RunRecord
  alias Jido.Integration.V2.StorePostgres.Serialization

  @impl true
  def put_run(%Run{} = run) do
    run
    |> to_record_attrs()
    |> then(&RunRecord.changeset(%RunRecord{}, &1))
    |> Repo.insert()
    |> case do
      {:ok, _record} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def fetch_run(run_id) do
    case Repo.get(RunRecord, run_id) do
      nil -> :error
      record -> {:ok, to_contract(record)}
    end
  end

  @impl true
  def update_run(run_id, status, result) do
    timestamp = Contracts.now()

    result =
      if is_nil(result), do: nil, else: result |> Redaction.redact() |> Serialization.dump()

    case Repo.update_all(
           from(run in RunRecord, where: run.run_id == ^run_id),
           set: [status: status, result: result, updated_at: timestamp]
         ) do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  def reset! do
    StorePostgres.assert_started!()
    Repo.delete_all(EventRecord)
    Repo.delete_all(AttemptRecord)
    Repo.delete_all(RunRecord)
    :ok
  end

  defp to_record_attrs(%Run{} = run) do
    %{
      run_id: run.run_id,
      capability_id: run.capability_id,
      runtime_class: run.runtime_class,
      status: run.status,
      input: run.input |> Redaction.redact() |> Serialization.dump(),
      credential_ref: Serialization.dump(run.credential_ref),
      target_id: run.target_id,
      result:
        if(is_nil(run.result),
          do: nil,
          else: run.result |> Redaction.redact() |> Serialization.dump()
        ),
      artifact_refs: Enum.map(run.artifact_refs, &Serialization.dump/1),
      inserted_at: run.inserted_at,
      updated_at: run.updated_at
    }
  end

  defp to_contract(record) do
    Run.new!(%{
      run_id: record.run_id,
      capability_id: record.capability_id,
      runtime_class: record.runtime_class,
      status: record.status,
      input: Serialization.load_json(record.input),
      credential_ref: to_credential_ref(record.credential_ref),
      target_id: record.target_id,
      result: Serialization.load_json(record.result),
      artifact_refs: Enum.map(record.artifact_refs || [], &to_artifact_ref/1),
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    })
  end

  defp to_credential_ref(map) do
    map = Serialization.load(map)

    CredentialRef.new!(%{
      id: Serialization.fetch(map, :id),
      subject: Serialization.fetch(map, :subject),
      scopes: Serialization.fetch(map, :scopes, []),
      metadata: Serialization.fetch(map, :metadata, %{})
    })
  end

  defp to_artifact_ref(map) do
    map = Serialization.load(map)

    ArtifactRef.new!(%{
      artifact_id: Serialization.fetch(map, :artifact_id),
      run_id: Serialization.fetch(map, :run_id),
      attempt_id: Serialization.fetch(map, :attempt_id),
      artifact_type: Serialization.fetch(map, :artifact_type),
      transport_mode: Serialization.fetch(map, :transport_mode),
      checksum: Serialization.fetch(map, :checksum),
      size_bytes: Serialization.fetch(map, :size_bytes),
      payload_ref: Serialization.fetch(map, :payload_ref),
      retention_class: Serialization.fetch(map, :retention_class),
      redaction_status: Serialization.fetch(map, :redaction_status),
      metadata: Serialization.fetch(map, :metadata, %{})
    })
  end
end
