defmodule Jido.Integration.V2.BrainIngress.SubmissionLedger do
  @moduledoc """
  Durable acceptance ledger for Brain submissions.
  """

  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.SubmissionRejection

  @callback accept_submission(BrainInvocation.t(), keyword()) ::
              {:ok, SubmissionAcceptance.t()} | {:error, term()}

  @callback fetch_acceptance(String.t(), keyword()) ::
              {:ok, SubmissionAcceptance.t()} | :error

  @callback record_rejection(String.t(), SubmissionRejection.t(), keyword()) ::
              :ok | {:error, term()}
end
