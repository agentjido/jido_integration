defmodule Jido.Integration.V2.BrainIngress.SubmissionLedger do
  @moduledoc """
  Durable acceptance ledger for Brain submissions.
  """

  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.SubmissionRejection

  @callback accept_submission(BrainInvocation.t(), keyword()) ::
              {:ok, SubmissionAcceptance.t()} | {:error, term()}

  @callback lookup_submission(String.t(), String.t(), keyword()) ::
              {:accepted, SubmissionAcceptance.t()}
              | {:rejected, SubmissionRejection.t()}
              | :never_seen
              | {:expired, DateTime.t()}

  @callback fetch_acceptance(String.t(), keyword()) ::
              {:ok, SubmissionAcceptance.t()} | :error

  @callback record_rejection(BrainInvocation.t(), SubmissionRejection.t(), keyword()) ::
              :ok | {:error, term()}

  @callback expire_submissions(keyword()) :: non_neg_integer() | {:error, term()}
end
