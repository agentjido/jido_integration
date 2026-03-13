defmodule Jido.Integration.Examples.HarnessCore.Dispatcher do
  @moduledoc """
  Dispatcher — the core harness orchestration loop.

  Implements the full trigger-to-terminal-result pipeline:

  1. **Target compatibility check** — reject if version or capabilities don't match
  2. **Policy enforcement** — gateway admission control with audit events
  3. **Adapter execution** — delegate to `Jido.Integration.execute/3`
  4. **Run event emission** — every stage produces an immutable run event

  ## Usage

      {:ok, agg} = RunAggregator.start_link()
      envelope = Envelope.new("ping", %{"message" => "hello"})

      {:ok, run_id, result} = Dispatcher.dispatch(HelloWorld, envelope, aggregator: agg)

      run = RunAggregator.get_run(agg, run_id)
      run.state  #=> :succeeded
  """

  alias Jido.Integration.Examples.HarnessCore.{RunAggregator, RunEvent}
  alias Jido.Integration.{Gateway, Operation}

  @type dispatch_result ::
          {:ok, String.t(), Operation.Result.t()}
          | {:error, String.t(), term()}
          | {:rejected, String.t(), String.t()}

  @doc """
  Dispatch an operation through the full harness pipeline.

  ## Options

  - `:aggregator` — RunAggregator pid (required)
  - `:run_id` — override the generated run ID
  - `:attempt_id` — attempt number (default: 1)
  - `:required_version` — minimum target version (e.g. "0.1.0")
  - `:required_capabilities` — list of capability keys the target must have
  - `:gateway_policies` — list of policy modules for admission control
  - `:gateway_pressure` — pressure map passed to policies
  - All other opts forwarded to `Jido.Integration.execute/3`
  """
  @spec dispatch(module(), Operation.Envelope.t(), keyword()) :: dispatch_result()
  def dispatch(adapter, %Operation.Envelope{} = envelope, opts) do
    aggregator = Keyword.fetch!(opts, :aggregator)
    run_id = Keyword.get(opts, :run_id, generate_id())
    attempt_id = Keyword.get(opts, :attempt_id, 1)

    manifest = adapter.manifest()

    with :ok <- check_target_compatibility(manifest, opts),
         :ok <- check_policy(manifest, envelope, opts) do
      # Emit dispatch_started
      emit(aggregator, run_id, attempt_id, 1, :dispatch_started, %{
        connector_id: manifest.id,
        operation_id: envelope.operation_id
      })

      # Execute through the integration control plane
      execute_opts =
        Keyword.drop(opts, [
          :aggregator,
          :run_id,
          :attempt_id,
          :required_version,
          :required_capabilities
        ])

      case Jido.Integration.execute(adapter, envelope, execute_opts) do
        {:ok, result} ->
          emit(aggregator, run_id, attempt_id, 2, :dispatch_succeeded, %{
            connector_id: manifest.id,
            operation_id: envelope.operation_id
          })

          {:ok, run_id, result}

        {:error, error} ->
          emit(aggregator, run_id, attempt_id, 2, :dispatch_failed, %{
            connector_id: manifest.id,
            operation_id: envelope.operation_id,
            error_class: error_class(error)
          })

          {:error, run_id, error}
      end
    else
      {:rejected, :target, reason} ->
        emit(aggregator, run_id, attempt_id, 1, :target_rejected, %{
          connector_id: manifest.id,
          reason: reason
        })

        {:rejected, run_id, reason}

      {:rejected, :policy, reason} ->
        emit(aggregator, run_id, attempt_id, 1, :policy_denied, %{
          connector_id: manifest.id,
          operation_id: envelope.operation_id,
          reason: reason
        })

        {:rejected, run_id, reason}
    end
  end

  # Target compatibility: version + capabilities

  defp check_target_compatibility(manifest, opts) do
    with :ok <- check_version(manifest, Keyword.get(opts, :required_version)),
         :ok <- check_capabilities(manifest, Keyword.get(opts, :required_capabilities, [])) do
      :ok
    else
      {:error, reason} -> {:rejected, :target, reason}
    end
  end

  defp check_version(_manifest, nil), do: :ok

  defp check_version(manifest, required_version) do
    case Version.compare(manifest.version, required_version) do
      :lt ->
        {:error, "Target version #{manifest.version} is below required #{required_version}"}

      _ ->
        :ok
    end
  end

  defp check_capabilities(_manifest, []), do: :ok

  defp check_capabilities(manifest, required) do
    missing = Enum.reject(required, &Map.has_key?(manifest.capabilities, &1))

    if missing == [] do
      :ok
    else
      {:error, "Missing required capabilities: #{Enum.join(missing, ", ")}"}
    end
  end

  # Policy enforcement

  defp check_policy(manifest, envelope, opts) do
    policies = Keyword.get(opts, :gateway_policies, [])

    if policies == [] do
      :ok
    else
      pressure = Keyword.get(opts, :gateway_pressure, %{})

      gateway_envelope = %{
        connector_id: manifest.id,
        operation_id: envelope.operation_id,
        context: envelope.context,
        auth_ref: envelope.auth_ref
      }

      case Gateway.check_chain(policies, gateway_envelope, pressure) do
        :admit -> :ok
        decision -> {:rejected, :policy, "Gateway #{decision}"}
      end
    end
  end

  # Event emission

  defp emit(aggregator, run_id, attempt_id, seq, event_type, payload) do
    event =
      RunEvent.new(
        run_id: run_id,
        attempt_id: attempt_id,
        seq: seq,
        event_type: event_type,
        payload: payload,
        connector_id: payload[:connector_id],
        operation_id: payload[:operation_id]
      )

    RunAggregator.append_event(aggregator, event)

    :telemetry.execute(
      [:jido, :integration, :harness, event_type],
      %{},
      Map.merge(payload, %{run_id: run_id, attempt_id: attempt_id, seq: seq})
    )

    event
  end

  defp error_class(%Jido.Integration.Error{class: class}), do: to_string(class)
  defp error_class(_), do: "unknown"

  defp generate_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end
