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

  alias Jido.Integration.V2.SubstrateReadSlice

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
          | :resolve_trace

  @doc """
  Return the bounded lower-read operation inventory exported by this facade.
  """
  @spec operations() :: [operation()]
  defdelegate operations(), to: SubstrateReadSlice

  @doc """
  Predicate for whether an operation belongs to the frozen lower-facts surface.
  """
  @spec operation_supported?(atom()) :: boolean()
  defdelegate operation_supported?(operation), to: SubstrateReadSlice

  @doc """
  Fetch a durable submission receipt by submission key.
  """
  defdelegate fetch_submission_receipt(scope, submission_key, opts \\ []),
    to: SubstrateReadSlice

  @doc """
  Fetch a previously recorded run.
  """
  defdelegate fetch_run(scope, run_id, opts \\ []), to: SubstrateReadSlice

  @doc """
  List recorded attempts for a run in durable attempt-number order.
  """
  defdelegate attempts(scope, run_id, opts \\ []), to: SubstrateReadSlice

  @doc """
  Fetch a previously recorded attempt.
  """
  defdelegate fetch_attempt(scope, attempt_id, opts \\ []), to: SubstrateReadSlice

  @doc """
  List canonical lower events for a run.
  """
  defdelegate events(scope, run_id_or_attempt_id, opts \\ []), to: SubstrateReadSlice

  @doc """
  Fetch a durable artifact reference by id.
  """
  defdelegate fetch_artifact(scope, artifact_id, opts \\ []), to: SubstrateReadSlice

  @doc """
  List durable artifact references for a run.
  """
  defdelegate run_artifacts(scope, run_id, opts \\ []), to: SubstrateReadSlice

  @doc """
  Resolve a scoped lower trace from a trace id or one of its lower ids.
  """
  defdelegate resolve_trace(scope, trace_or_lower_id, opts \\ []), to: SubstrateReadSlice
end
