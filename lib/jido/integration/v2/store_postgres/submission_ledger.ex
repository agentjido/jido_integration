defmodule Jido.Integration.V2.StorePostgres.SubmissionLedger do
  @moduledoc false

  @behaviour Jido.Integration.V2.BrainIngress.SubmissionLedger

  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.SubmissionRecord
  alias Jido.Integration.V2.StorePostgres.Serialization
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.SubmissionIdentity
  alias Jido.Integration.V2.SubmissionRejection

  @impl true
  def accept_submission(%BrainInvocation{} = invocation, _opts) do
    identity_checksum = SubmissionIdentity.submission_key(invocation.submission_identity)

    acceptance =
      SubmissionAcceptance.new!(%{
        submission_key: invocation.submission_key,
        submission_receipt_ref: "submission://postgres/#{invocation.submission_key}",
        status: :accepted,
        ledger_version: 1
      })

    attrs = %{
      submission_key: invocation.submission_key,
      identity_checksum: identity_checksum,
      status: "accepted",
      acceptance_json: Serialization.dump(SubmissionAcceptance.dump(acceptance)),
      rejection_json: nil
    }

    %SubmissionRecord{}
    |> SubmissionRecord.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, _record} ->
        {:ok, acceptance}

      {:error, changeset} ->
        with true <- duplicate_submission_key?(changeset),
             %SubmissionRecord{} = record <- Repo.get(SubmissionRecord, invocation.submission_key),
             true <- record.identity_checksum == identity_checksum do
          duplicate =
            record.acceptance_json
            |> Serialization.load_json()
            |> SubmissionAcceptance.new!()
            |> SubmissionAcceptance.dump()
            |> Map.put(:status, :duplicate)
            |> SubmissionAcceptance.new!()

          {:ok, duplicate}
        else
          _other -> {:error, :conflicting_submission}
        end
    end
  end

  @impl true
  def fetch_acceptance(submission_key, _opts) do
    case Repo.get(SubmissionRecord, submission_key) do
      %SubmissionRecord{acceptance_json: acceptance_json} when is_map(acceptance_json) ->
        {:ok, acceptance_json |> Serialization.load_json() |> SubmissionAcceptance.new!()}

      _other ->
        :error
    end
  end

  @impl true
  def record_rejection(submission_key, %SubmissionRejection{} = rejection, _opts) do
    identity_checksum = rejection.submission_key

    attrs = %{
      submission_key: submission_key,
      identity_checksum: identity_checksum,
      status: "rejected",
      acceptance_json: nil,
      rejection_json: Serialization.dump(SubmissionRejection.dump(rejection))
    }

    case Repo.get(SubmissionRecord, submission_key) do
      nil ->
        %SubmissionRecord{}
        |> SubmissionRecord.changeset(attrs)
        |> Repo.insert()
        |> case do
          {:ok, _record} -> :ok
          {:error, reason} -> {:error, reason}
        end

      %SubmissionRecord{} = record ->
        record
        |> SubmissionRecord.changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, _record} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp duplicate_submission_key?(changeset) do
    Enum.any?(changeset.errors, fn {field, {_message, metadata}} ->
      field == :submission_key and metadata[:constraint] in [:unique, :unsafe_unique]
    end)
  end
end
