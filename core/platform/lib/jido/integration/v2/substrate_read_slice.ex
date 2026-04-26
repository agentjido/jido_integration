defmodule Jido.Integration.V2.SubstrateReadSlice do
  @moduledoc """
  Tenant-scoped substrate-facing read slice over lower execution facts.

  This module is the dedicated Mezzanine readback seam. It does not assemble
  operator packets, review aggregates, or product-specific projections.
  """

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.BrainIngress
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.Receipt
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.TenantScope

  @type operation ::
          :fetch_submission_receipt
          | :fetch_run
          | :attempts
          | :fetch_attempt
          | :events
          | :fetch_artifact
          | :run_artifacts
          | :fetch_execution_outcome
          | :resolve_trace

  @type failure ::
          :tenant_mismatch
          | :installation_mismatch
          | :not_found
          | :stale
          | :unavailable
          | {:invalid_scope, term()}

  @operations [
    :fetch_submission_receipt,
    :fetch_run,
    :attempts,
    :fetch_attempt,
    :events,
    :fetch_artifact,
    :run_artifacts,
    :fetch_execution_outcome,
    :resolve_trace
  ]

  @spec operations() :: [operation()]
  def operations, do: @operations

  @spec operation_supported?(atom()) :: boolean()
  def operation_supported?(operation) when is_atom(operation), do: operation in @operations

  @spec fetch_submission_receipt(TenantScope.t(), String.t(), keyword()) ::
          {:ok, SubmissionAcceptance.t()} | {:error, failure()}
  def fetch_submission_receipt(scope, submission_key, opts \\ [])

  def fetch_submission_receipt(scope, submission_key, opts)
      when is_binary(submission_key) and is_list(opts) do
    with {:ok, %TenantScope{} = scope} <- normalize_scope(scope) do
      fetch_acceptance(scope, submission_key, opts)
    end
  end

  def fetch_submission_receipt(scope, _submission_key, _opts) do
    with {:ok, _scope} <- normalize_scope(scope), do: {:error, :not_found}
  end

  @spec fetch_run(TenantScope.t(), String.t(), keyword()) :: {:ok, Run.t()} | {:error, failure()}
  def fetch_run(scope, run_id, opts \\ [])

  def fetch_run(scope, run_id, _opts) when is_binary(run_id) do
    with {:ok, %TenantScope{} = scope} <- normalize_scope(scope),
         {:ok, %Run{} = run} <- fetch_run_record(run_id),
         :ok <- authorize_run(scope, run) do
      {:ok, run}
    end
  end

  def fetch_run(scope, _run_id, _opts) do
    with {:ok, _scope} <- normalize_scope(scope), do: {:error, :not_found}
  end

  @spec attempts(TenantScope.t(), String.t(), keyword()) ::
          {:ok, [Attempt.t()]} | {:error, failure()}
  def attempts(scope, run_id, opts \\ [])

  def attempts(scope, run_id, _opts) when is_binary(run_id) do
    with {:ok, %TenantScope{} = scope} <- normalize_scope(scope),
         {:ok, %Run{} = run} <- fetch_run_record(run_id),
         :ok <- authorize_run(scope, run) do
      {:ok, ControlPlane.attempts(run.run_id)}
    end
  end

  def attempts(scope, _run_id, _opts) do
    with {:ok, _scope} <- normalize_scope(scope), do: {:error, :not_found}
  end

  @spec fetch_attempt(TenantScope.t(), String.t(), keyword()) ::
          {:ok, Attempt.t()} | {:error, failure()}
  def fetch_attempt(scope, attempt_id, opts \\ [])

  def fetch_attempt(scope, attempt_id, _opts) when is_binary(attempt_id) do
    with {:ok, %TenantScope{} = scope} <- normalize_scope(scope),
         {:ok, %Attempt{} = attempt} <- fetch_attempt_record(attempt_id),
         {:ok, %Run{} = run} <- fetch_run_record(attempt.run_id),
         :ok <- authorize_run(scope, run) do
      {:ok, attempt}
    end
  end

  def fetch_attempt(scope, _attempt_id, _opts) do
    with {:ok, _scope} <- normalize_scope(scope), do: {:error, :not_found}
  end

  @spec events(TenantScope.t(), String.t(), keyword()) :: {:ok, [Event.t()]} | {:error, failure()}
  def events(scope, run_id_or_attempt_id, opts \\ [])

  def events(scope, run_id_or_attempt_id, _opts) when is_binary(run_id_or_attempt_id) do
    with {:ok, %TenantScope{} = scope} <- normalize_scope(scope),
         {:ok, %Run{} = run} <- resolve_run_from_run_or_attempt(run_id_or_attempt_id),
         :ok <- authorize_run(scope, run) do
      {:ok, ControlPlane.events(run.run_id)}
    end
  end

  def events(scope, _run_id_or_attempt_id, _opts) do
    with {:ok, _scope} <- normalize_scope(scope), do: {:error, :not_found}
  end

  @spec fetch_artifact(TenantScope.t(), String.t(), keyword()) ::
          {:ok, ArtifactRef.t()} | {:error, failure()}
  def fetch_artifact(scope, artifact_id, opts \\ [])

  def fetch_artifact(scope, artifact_id, _opts) when is_binary(artifact_id) do
    with {:ok, %TenantScope{} = scope} <- normalize_scope(scope),
         {:ok, %ArtifactRef{} = artifact} <- fetch_artifact_record(artifact_id),
         {:ok, %Run{} = run} <- fetch_run_record(artifact.run_id),
         :ok <- authorize_run(scope, run) do
      {:ok, artifact}
    end
  end

  def fetch_artifact(scope, _artifact_id, _opts) do
    with {:ok, _scope} <- normalize_scope(scope), do: {:error, :not_found}
  end

  @spec run_artifacts(TenantScope.t(), String.t(), keyword()) ::
          {:ok, [ArtifactRef.t()]} | {:error, failure()}
  def run_artifacts(scope, run_id, opts \\ [])

  def run_artifacts(scope, run_id, _opts) when is_binary(run_id) do
    with {:ok, %TenantScope{} = scope} <- normalize_scope(scope),
         {:ok, %Run{} = run} <- fetch_run_record(run_id),
         :ok <- authorize_run(scope, run) do
      {:ok, ControlPlane.run_artifacts(run.run_id)}
    end
  end

  def run_artifacts(scope, _run_id, _opts) do
    with {:ok, _scope} <- normalize_scope(scope), do: {:error, :not_found}
  end

  @spec fetch_execution_outcome(TenantScope.t(), map(), keyword()) ::
          :pending | {:ok, map()} | {:error, failure()}
  def fetch_execution_outcome(scope, execution_lookup, opts \\ [])

  def fetch_execution_outcome(scope, execution_lookup, opts)
      when is_map(execution_lookup) and is_list(opts) do
    with {:ok, %TenantScope{} = scope} <- normalize_scope(scope),
         {:ok, %Run{} = run} <- resolve_run_from_execution_lookup(execution_lookup),
         :ok <- authorize_run(scope, run) do
      execution_outcome(run, execution_lookup, opts)
    end
  end

  def fetch_execution_outcome(scope, _execution_lookup, _opts) do
    with {:ok, _scope} <- normalize_scope(scope), do: {:error, :not_found}
  end

  @spec resolve_trace(TenantScope.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, failure()}
  def resolve_trace(scope, trace_or_lower_id, opts \\ [])

  def resolve_trace(scope, trace_or_lower_id, _opts) when is_binary(trace_or_lower_id) do
    with {:ok, %TenantScope{} = scope} <- normalize_scope(scope),
         {:ok, %Run{} = run} <- resolve_run(trace_or_lower_id),
         :ok <- authorize_run(scope, run) do
      {:ok,
       %{
         trace_id: trace_id(run, ControlPlane.events(run.run_id)),
         run: run,
         attempts: ControlPlane.attempts(run.run_id),
         events: ControlPlane.events(run.run_id),
         artifacts: ControlPlane.run_artifacts(run.run_id)
       }}
    end
  end

  def resolve_trace(scope, _trace_or_lower_id, _opts) do
    with {:ok, _scope} <- normalize_scope(scope), do: {:error, :not_found}
  end

  defp fetch_acceptance(%TenantScope{} = scope, submission_key, opts) do
    opts =
      Keyword.update(
        opts,
        :submission_ledger_opts,
        [tenant_id: scope.tenant_id],
        fn ledger_opts ->
          Keyword.put(ledger_opts, :tenant_id, scope.tenant_id)
        end
      )

    case BrainIngress.fetch_acceptance(submission_key, opts) do
      {:ok, %SubmissionAcceptance{} = receipt} -> {:ok, receipt}
      {:error, :tenant_mismatch} -> {:error, :tenant_mismatch}
      :error -> {:error, :not_found}
    end
  end

  defp normalize_scope(%TenantScope{} = scope), do: {:ok, scope}
  defp normalize_scope(_scope), do: {:error, {:invalid_scope, :typed_tenant_scope_required}}

  defp fetch_run_record(run_id) do
    case ControlPlane.fetch_run(run_id) do
      {:ok, %Run{} = run} -> {:ok, run}
      :error -> {:error, :not_found}
    end
  end

  defp fetch_attempt_record(attempt_id) do
    case ControlPlane.fetch_attempt(attempt_id) do
      {:ok, %Attempt{} = attempt} -> {:ok, attempt}
      :error -> {:error, :not_found}
    end
  end

  defp fetch_artifact_record(artifact_id) do
    case ControlPlane.fetch_artifact(artifact_id) do
      {:ok, %ArtifactRef{} = artifact} -> {:ok, artifact}
      :error -> {:error, :not_found}
    end
  end

  defp resolve_run_from_execution_lookup(execution_lookup) do
    execution_lookup
    |> execution_lookup_identifiers()
    |> Enum.reduce_while({:error, :not_found}, fn identifier, _acc ->
      case resolve_run(identifier) do
        {:ok, %Run{} = run} -> {:halt, {:ok, run}}
        {:error, :not_found} -> {:cont, {:error, :not_found}}
      end
    end)
  end

  defp execution_lookup_identifiers(execution_lookup) do
    [
      lookup_value(execution_lookup, [:lower_receipt, :run_id]),
      lookup_value(execution_lookup, [:lower_receipt, :attempt_id]),
      lookup_value(execution_lookup, [:submission_ref, :run_id]),
      lookup_value(execution_lookup, [:submission_ref, :attempt_id]),
      lookup_value(execution_lookup, [:run_id]),
      lookup_value(execution_lookup, [:attempt_id]),
      lookup_value(execution_lookup, [:artifact_id]),
      lookup_value(execution_lookup, [:trace_id]),
      lookup_value(execution_lookup, [:lower_run_id]),
      lookup_value(execution_lookup, [:lower_attempt_id]),
      lookup_value(execution_lookup, [:lower_artifact_id])
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp execution_outcome(%Run{status: status}, _execution_lookup, _opts)
       when status in [:accepted, :running],
       do: :pending

  defp execution_outcome(%Run{} = run, execution_lookup, opts) do
    with {:ok, attempt} <- execution_lookup_attempt(run, execution_lookup) do
      events = ControlPlane.events(run.run_id)
      artifacts = ControlPlane.run_artifacts(run.run_id)

      receipt =
        Receipt.from_lower_records!(
          run,
          attempt,
          events,
          artifacts,
          receipt_opts(run, execution_lookup, opts)
        )

      case Receipt.to_execution_outcome(receipt, normalized_outcome(run, attempt)) do
        {:ok, outcome} -> {:ok, outcome}
        {:error, {:non_terminal_receipt, _status}} -> :pending
      end
    end
  end

  defp execution_lookup_attempt(%Run{} = run, execution_lookup) do
    case lookup_attempt_id(execution_lookup) do
      nil ->
        {:ok, latest_attempt(run)}

      attempt_id ->
        with {:ok, %Attempt{} = attempt} <- fetch_attempt_record(attempt_id),
             true <- attempt.run_id == run.run_id do
          {:ok, attempt}
        else
          false -> {:error, :stale}
          {:error, :not_found} -> {:error, :not_found}
        end
    end
  end

  defp lookup_attempt_id(execution_lookup) do
    first_present([
      lookup_value(execution_lookup, [:lower_receipt, :attempt_id]),
      lookup_value(execution_lookup, [:submission_ref, :attempt_id]),
      lookup_value(execution_lookup, [:attempt_id]),
      lookup_value(execution_lookup, [:lower_attempt_id])
    ])
  end

  defp latest_attempt(%Run{} = run) do
    run.run_id
    |> ControlPlane.attempts()
    |> Enum.max_by(& &1.attempt, fn -> nil end)
  end

  defp receipt_opts(%Run{} = run, execution_lookup, opts) do
    [
      ji_submission_key: ji_submission_key(run, execution_lookup),
      normalized_outcome_ref:
        lookup_value(execution_lookup, [:lower_receipt, :normalized_outcome_ref]),
      lifecycle_hints: lookup_value(execution_lookup, [:lower_receipt, :lifecycle_hints]) || %{},
      failure_kind: lookup_value(execution_lookup, [:lower_receipt, :failure_kind])
    ]
    |> Keyword.merge(opts)
  end

  defp ji_submission_key(%Run{} = run, execution_lookup) do
    first_present([
      lookup_value(execution_lookup, [:lower_receipt, :ji_submission_key]),
      lookup_value(execution_lookup, [:submission_ref, :ji_submission_key]),
      fetch_path(run.input, [:metadata, :ji_submission_key]),
      fetch_path(run.input, [:request, :metadata, :ji_submission_key])
    ])
  end

  defp normalized_outcome(%Run{}, %Attempt{output: output}) when is_map(output), do: output
  defp normalized_outcome(%Run{result: result}, _attempt) when is_map(result), do: result
  defp normalized_outcome(_run, _attempt), do: %{}

  defp resolve_run_from_run_or_attempt(identifier) do
    case fetch_attempt_record(identifier) do
      {:ok, %Attempt{} = attempt} -> fetch_run_record(attempt.run_id)
      {:error, :not_found} -> fetch_run_record(identifier)
    end
  end

  defp resolve_run(identifier) do
    with {:error, :not_found} <- fetch_run_record(identifier),
         {:error, :not_found} <- resolve_run_from_attempt(identifier),
         {:error, :not_found} <- resolve_run_from_artifact(identifier) do
      resolve_run_from_trace(identifier)
    end
  end

  defp resolve_run_from_attempt(identifier) do
    case fetch_attempt_record(identifier) do
      {:ok, %Attempt{} = attempt} -> fetch_run_record(attempt.run_id)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp resolve_run_from_artifact(identifier) do
    case fetch_artifact_record(identifier) do
      {:ok, %ArtifactRef{} = artifact} -> fetch_run_record(artifact.run_id)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp resolve_run_from_trace(trace_id) do
    ControlPlane.runs(%{})
    |> Enum.find(fn %Run{} = run ->
      run_events = ControlPlane.events(run.run_id)
      trace_id(run, run_events) == trace_id
    end)
    |> case do
      %Run{} = run -> {:ok, run}
      nil -> {:error, :not_found}
    end
  end

  defp authorize_run(%TenantScope{} = scope, %Run{} = run) do
    cond do
      tenant_id(run) != scope.tenant_id ->
        {:error, :tenant_mismatch}

      scope.installation_id &&
        installation_id(run) &&
          installation_id(run) != scope.installation_id ->
        {:error, :installation_mismatch}

      true ->
        :ok
    end
  end

  defp tenant_id(%Run{} = run) do
    first_present([
      fetch_path(run.input, [:context, :metadata, :tenant_id]),
      fetch_path(run.input, [:request, :metadata, :tenant_id]),
      fetch_path(run.input, [:metadata, :tenant_id]),
      fetch_path(run.input, [:trigger, :tenant_id]),
      fetch_path(run.input, [:tenant_id])
    ])
  end

  defp installation_id(%Run{} = run) do
    first_present([
      fetch_path(run.input, [:context, :metadata, :installation_id]),
      fetch_path(run.input, [:request, :metadata, :installation_id]),
      fetch_path(run.input, [:metadata, :installation_id]),
      fetch_path(run.input, [:installation_id])
    ])
  end

  defp trace_id(%Run{} = run, events) do
    first_present([
      trace_id_from_events(events),
      fetch_path(run.input, [:context, :observability, :trace_id]),
      fetch_path(run.input, [:context, :metadata, :trace_id]),
      fetch_path(run.input, [:request, :metadata, :trace_id]),
      fetch_path(run.input, [:metadata, :trace_id]),
      fetch_path(run.input, [:trace_id])
    ])
  end

  defp trace_id_from_events(events) do
    Enum.find_value(events, fn %Event{} = event ->
      event.trace
      |> Contracts.get(:trace_id)
      |> present_value()
    end)
  end

  defp fetch_path(value, []), do: present_value(value)

  defp fetch_path(value, [key | rest]) when is_map(value) do
    value
    |> Contracts.get(key)
    |> fetch_path(rest)
  end

  defp fetch_path(_value, _path), do: nil

  defp lookup_value(value, path), do: fetch_path(value, path)

  defp first_present(values), do: Enum.find_value(values, &present_value/1)

  defp present_value(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp present_value(_value), do: nil
end
