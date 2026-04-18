defmodule Jido.Integration.V2.StoreLocal.SubmissionLedger do
  @moduledoc false

  @behaviour Jido.Integration.V2.BrainIngress.SubmissionLedger

  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.StoreLocal.State
  alias Jido.Integration.V2.StoreLocal.Storage
  alias Jido.Integration.V2.SubmissionRejection

  @impl true
  def accept_submission(%BrainInvocation{} = invocation, _opts) do
    Storage.mutate(&State.accept_submission(&1, invocation))
  end

  @impl true
  def lookup_submission(submission_dedupe_key, tenant_id, _opts) do
    Storage.read(&State.lookup_submission(&1, submission_dedupe_key, tenant_id))
  end

  @impl true
  def fetch_acceptance(submission_key, _opts) do
    Storage.read(&State.fetch_submission_acceptance(&1, submission_key))
  end

  @impl true
  def record_rejection(%BrainInvocation{} = invocation, %SubmissionRejection{} = rejection, _opts) do
    Storage.mutate(&State.record_submission_rejection(&1, invocation, rejection))
  end

  @impl true
  def expire_submissions(opts) do
    Storage.mutate(&State.expire_submissions(&1, Keyword.get(opts, :now)))
  end

  def reset! do
    Storage.mutate(&State.reset_submission_ledger/1)
  end
end
