defmodule Jido.Integration.V2.LowerFacts do
  @moduledoc """
  Bounded substrate-facing read facade over generic lower execution facts.

  This module intentionally exposes only lower truth that remains generic across
  higher-order repos:

  - submission receipts
  - run state
  - attempt state
  - event streams
  - artifact refs

  It does not assemble operator packets, review aggregates, or product-specific
  projections.
  """

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.BrainIngress
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.SubmissionAcceptance

  @typedoc """
  Stable lower-read operations exposed to higher-order substrate bridges.
  """
  @type operation ::
          :fetch_submission_receipt
          | :fetch_run
          | :attempts
          | :fetch_attempt
          | :events
          | :fetch_artifact
          | :run_artifacts

  @operations [
    :fetch_submission_receipt,
    :fetch_run,
    :attempts,
    :fetch_attempt,
    :events,
    :fetch_artifact,
    :run_artifacts
  ]

  @doc """
  Return the bounded lower-read operation inventory exported by this facade.
  """
  @spec operations() :: [operation()]
  def operations, do: @operations

  @doc """
  Predicate for whether an operation belongs to the frozen lower-facts surface.
  """
  @spec operation_supported?(atom()) :: boolean()
  def operation_supported?(operation) when is_atom(operation), do: operation in @operations

  @doc """
  Fetch a durable submission receipt by submission key.
  """
  @spec fetch_submission_receipt(String.t(), keyword()) ::
          {:ok, SubmissionAcceptance.t()} | :error
  def fetch_submission_receipt(submission_key, opts \\ []) when is_binary(submission_key) do
    BrainIngress.fetch_acceptance(submission_key, opts)
  end

  @doc """
  Fetch a previously recorded run.
  """
  @spec fetch_run(String.t()) :: {:ok, Run.t()} | :error
  defdelegate fetch_run(run_id), to: ControlPlane

  @doc """
  List recorded attempts for a run in durable attempt-number order.
  """
  @spec attempts(String.t()) :: [Attempt.t()]
  defdelegate attempts(run_id), to: ControlPlane

  @doc """
  Fetch a previously recorded attempt.
  """
  @spec fetch_attempt(String.t()) :: {:ok, Attempt.t()} | :error
  defdelegate fetch_attempt(attempt_id), to: ControlPlane

  @doc """
  List canonical lower events for a run.
  """
  @spec events(String.t()) :: [Event.t()]
  defdelegate events(run_id), to: ControlPlane

  @doc """
  Fetch a durable artifact reference by id.
  """
  @spec fetch_artifact(String.t()) :: {:ok, ArtifactRef.t()} | :error
  defdelegate fetch_artifact(artifact_id), to: ControlPlane

  @doc """
  List durable artifact references for a run.
  """
  @spec run_artifacts(String.t()) :: [ArtifactRef.t()]
  defdelegate run_artifacts(run_id), to: ControlPlane
end
