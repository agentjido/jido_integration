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
  def fetch_acceptance(submission_key, _opts) do
    Storage.read(&State.fetch_submission_acceptance(&1, submission_key))
  end

  @impl true
  def record_rejection(submission_key, %SubmissionRejection{} = rejection, _opts) do
    Storage.mutate(&State.record_submission_rejection(&1, submission_key, rejection))
  end

  def reset! do
    Storage.mutate(&State.reset_submission_ledger/1)
  end
end
