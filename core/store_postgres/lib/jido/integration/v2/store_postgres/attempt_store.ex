defmodule Jido.Integration.V2.StorePostgres.AttemptStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.AttemptStore

  import Ecto.Query

  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane.Stores
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.AttemptRecord
  alias Jido.Integration.V2.StorePostgres.Serialization

  @impl true
  def put_attempt(%Attempt{} = attempt) do
    Repo.transaction(fn ->
      attempt
      |> to_record_attrs()
      |> then(&AttemptRecord.changeset(%AttemptRecord{}, &1))
      |> Repo.insert()
      |> case do
        {:ok, _record} ->
          :ok = register_attempt_payload_refs(attempt)
          :ok

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> normalize_transaction()
  end

  @impl true
  def fetch_attempt(attempt_id) do
    case Repo.get(AttemptRecord, attempt_id) do
      nil -> :error
      record -> {:ok, to_contract(record)}
    end
  end

  @impl true
  def list_attempts(run_id) do
    from(attempt in AttemptRecord,
      where: attempt.run_id == ^run_id,
      order_by: [asc: attempt.attempt, asc: attempt.attempt_id]
    )
    |> Repo.all()
    |> Enum.map(&to_contract/1)
  end

  @impl true
  def update_attempt(attempt_id, status, output, runtime_ref_id, opts \\ []) do
    Repo.transaction(fn ->
      record =
        case Repo.get(AttemptRecord, attempt_id) do
          nil -> Repo.rollback(:not_found)
          record -> record
        end

      next_epoch = Keyword.get(opts, :aggregator_epoch, record.aggregator_epoch)

      if next_epoch < record.aggregator_epoch do
        Repo.rollback(:stale_aggregator_epoch)
      end

      aggregator_id = Keyword.get(opts, :aggregator_id, record.aggregator_id)
      timestamp = Contracts.now()

      case Repo.update_all(
             from(attempt in AttemptRecord,
               where:
                 attempt.attempt_id == ^attempt_id and attempt.aggregator_epoch <= ^next_epoch
             ),
             set: [
               status: status,
               output:
                 if(is_nil(output),
                   do: nil,
                   else: output |> Redaction.redact() |> Serialization.dump()
                 ),
               runtime_ref_id: runtime_ref_id,
               aggregator_id: aggregator_id,
               aggregator_epoch: next_epoch,
               updated_at: timestamp
             ]
           ) do
        {1, _} -> :ok
        _ -> Repo.rollback(:stale_aggregator_epoch)
      end
    end)
    |> normalize_transaction()
  end

  def reset! do
    StorePostgres.assert_started!()
    Repo.delete_all(AttemptRecord)
    :ok
  end

  defp normalize_transaction({:ok, result}), do: result
  defp normalize_transaction({:error, reason}), do: {:error, reason}

  defp to_record_attrs(%Attempt{} = attempt) do
    %{
      attempt_id: attempt.attempt_id,
      run_id: attempt.run_id,
      attempt: attempt.attempt,
      aggregator_id: attempt.aggregator_id,
      aggregator_epoch: attempt.aggregator_epoch,
      runtime_class: attempt.runtime_class,
      status: attempt.status,
      credential_lease_id: attempt.credential_lease_id,
      target_id: attempt.target_id,
      runtime_ref_id: attempt.runtime_ref_id,
      output:
        if(is_nil(attempt.output),
          do: nil,
          else: attempt.output |> Redaction.redact() |> Serialization.dump()
        ),
      output_payload_ref:
        if(is_nil(attempt.output_payload_ref),
          do: nil,
          else: Serialization.dump(attempt.output_payload_ref)
        ),
      inserted_at: attempt.inserted_at,
      updated_at: attempt.updated_at
    }
  end

  defp to_contract(record) do
    Attempt.new!(%{
      attempt_id: record.attempt_id,
      run_id: record.run_id,
      attempt: record.attempt,
      aggregator_id: record.aggregator_id,
      aggregator_epoch: record.aggregator_epoch,
      runtime_class: record.runtime_class,
      status: record.status,
      credential_lease_id: record.credential_lease_id,
      target_id: record.target_id,
      runtime_ref_id: record.runtime_ref_id,
      output: Serialization.load_json(record.output),
      output_payload_ref: Serialization.load_json(record.output_payload_ref),
      inserted_at: record.inserted_at,
      updated_at: record.updated_at
    })
  end

  defp register_attempt_payload_refs(%Attempt{} = attempt) do
    case attempt.output_payload_ref do
      nil ->
        :ok

      payload_ref ->
        Stores.claim_check_store().register_reference(payload_ref, %{
          ledger_kind: :attempt,
          ledger_id: attempt.attempt_id,
          payload_field: :output,
          run_id: attempt.run_id,
          attempt_id: attempt.attempt_id
        })
    end
  end
end
