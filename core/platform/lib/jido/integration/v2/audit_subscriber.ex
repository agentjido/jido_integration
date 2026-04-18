defmodule Jido.Integration.V2.AuditSubscriber do
  @moduledoc """
  Bounded observer export seam over durable lower facts.

  Replay is scoped by `run_id` and filtered only by the frozen Stage 14 export
  kinds. This module does not expose arbitrary lower-id fetches, live PubSub
  taps, or product-facing query surfaces.
  """

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.AuditExportEnvelope
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.ControlPlane.ClaimCheck
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.Run

  @export_kinds AuditExportEnvelope.export_kinds()
  @diagnostic_trace_id "diagnostic.missing_trace_id"
  @diagnostic_tenant_id "diagnostic.missing_tenant_id"

  @type export_filter_error :: :invalid_event_types

  @doc """
  Return the frozen export kinds supported by the audit-subscriber seam.
  """
  @spec export_kinds() :: [AuditExportEnvelope.export_kind(), ...]
  def export_kinds, do: @export_kinds

  @doc """
  Replay typed observer exports for one durable run lineage.

  Supported options:

  - `:event_types` limits replay to the frozen export kinds
  """
  def replay(run_id, opts \\ [])

  @spec replay(String.t(), keyword()) ::
          {:ok, [AuditExportEnvelope.t()]} | {:error, :unknown_run | export_filter_error()}
  def replay(run_id, opts) when is_binary(run_id) do
    with {:ok, selected_kinds} <- normalize_event_types(Keyword.get(opts, :event_types)),
         {:ok, %Run{} = run} <- ControlPlane.fetch_run(run_id) do
      attempts =
        run_id
        |> ControlPlane.attempts()
        |> Enum.sort_by(& &1.attempt)

      events =
        run_id
        |> ControlPlane.events()
        |> Enum.sort_by(&{&1.attempt || 0, &1.seq, &1.event_id})

      artifacts =
        run_id
        |> ControlPlane.run_artifacts()
        |> Enum.sort_by(&{&1.attempt_id, &1.artifact_id})

      scope = scope_metadata(run, events)

      envelopes =
        []
        |> maybe_put_run_export(run, selected_kinds, scope)
        |> maybe_put_attempt_exports(attempts, selected_kinds, scope)
        |> maybe_put_event_exports(events, selected_kinds, scope)
        |> maybe_put_artifact_exports(artifacts, selected_kinds, scope)

      {:ok, envelopes}
    else
      :error -> {:error, :unknown_run}
      {:error, :invalid_event_types} = error -> error
    end
  end

  def replay(_run_id, _opts), do: {:error, :unknown_run}

  defp maybe_put_run_export(exports, %Run{} = run, selected_kinds, scope) do
    if MapSet.member?(selected_kinds, "run.accepted") do
      [run_export(run, scope) | exports]
    else
      exports
    end
  end

  defp maybe_put_attempt_exports(exports, attempts, selected_kinds, scope) do
    if MapSet.member?(selected_kinds, "attempt.recorded") do
      exports ++ Enum.map(attempts, &attempt_export(&1, scope))
    else
      exports
    end
  end

  defp maybe_put_event_exports(exports, events, selected_kinds, scope) do
    if MapSet.member?(selected_kinds, "event.appended") do
      exports ++ Enum.map(events, &event_export(&1, scope))
    else
      exports
    end
  end

  defp maybe_put_artifact_exports(exports, artifacts, selected_kinds, scope) do
    if MapSet.member?(selected_kinds, "artifact.recorded") do
      exports ++ Enum.map(artifacts, &artifact_export(&1, scope))
    else
      exports
    end
  end

  defp run_export(%Run{} = run, scope) do
    input_resolution = resolve_optional_json(run.input, run.input_payload_ref)
    result_resolution = resolve_optional_json(run.result, run.result_payload_ref)

    payload =
      payload_with_diagnostics(
        "run",
        run
        |> Map.from_struct()
        |> Map.put(:input, input_resolution.payload)
        |> Map.put(:result, result_resolution.payload),
        input_resolution.diagnostics
        |> Map.merge(result_resolution.diagnostics)
        |> Map.merge(scope.diagnostics)
      )

    AuditExportEnvelope.new!(%{
      export_id: export_id("run.accepted", run.run_id),
      export_kind: "run.accepted",
      trace_id: scope.trace_id,
      tenant_id: scope.tenant_id,
      installation_id: scope.installation_id,
      run_id: run.run_id,
      attempt_id: nil,
      event_id: nil,
      staleness: envelope_staleness(scope, [input_resolution, result_resolution]),
      payload: payload
    })
  end

  defp attempt_export(%Attempt{} = attempt, scope) do
    output_resolution = resolve_optional_json(attempt.output, attempt.output_payload_ref)

    payload =
      payload_with_diagnostics(
        "attempt",
        attempt
        |> Map.from_struct()
        |> Map.put(:output, output_resolution.payload),
        Map.merge(output_resolution.diagnostics, scope.diagnostics)
      )

    AuditExportEnvelope.new!(%{
      export_id: export_id("attempt.recorded", attempt.attempt_id),
      export_kind: "attempt.recorded",
      trace_id: scope.trace_id,
      tenant_id: scope.tenant_id,
      installation_id: scope.installation_id,
      run_id: attempt.run_id,
      attempt_id: attempt.attempt_id,
      event_id: nil,
      staleness: envelope_staleness(scope, [output_resolution]),
      payload: payload
    })
  end

  defp event_export(%Event{} = event, scope) do
    payload_resolution = resolve_optional_json(event.payload, event.payload_ref)
    event_trace_id = Contracts.get(event.trace, :trace_id) || scope.trace_id

    payload =
      payload_with_diagnostics(
        "event",
        event
        |> Map.from_struct()
        |> Map.put(:payload, payload_resolution.payload)
        |> Map.put(:trace, Map.put(event.trace, :trace_id, event_trace_id)),
        Map.merge(payload_resolution.diagnostics, scope.diagnostics)
      )

    event_scope = event_scope(scope, event_trace_id)

    AuditExportEnvelope.new!(%{
      export_id: export_id("event.appended", event.event_id),
      export_kind: "event.appended",
      trace_id: event_scope.trace_id,
      tenant_id: event_scope.tenant_id,
      installation_id: event_scope.installation_id,
      run_id: event.run_id,
      attempt_id: event.attempt_id,
      event_id: event.event_id,
      staleness: envelope_staleness(event_scope, [payload_resolution]),
      payload: payload
    })
  end

  defp artifact_export(%ArtifactRef{} = artifact, scope) do
    payload =
      payload_with_diagnostics(
        "artifact",
        Map.from_struct(artifact),
        scope.diagnostics
      )

    AuditExportEnvelope.new!(%{
      export_id: export_id("artifact.recorded", artifact.artifact_id),
      export_kind: "artifact.recorded",
      trace_id: scope.trace_id,
      tenant_id: scope.tenant_id,
      installation_id: scope.installation_id,
      run_id: artifact.run_id,
      attempt_id: artifact.attempt_id,
      event_id: nil,
      staleness: envelope_staleness(scope, []),
      payload: payload
    })
  end

  defp scope_metadata(%Run{} = run, events) do
    input_resolution = resolve_optional_json(run.input, run.input_payload_ref)
    resolved_input = input_resolution.payload || %{}

    trace_id =
      first_present([
        trace_id_from_events(events),
        fetch_path(resolved_input, [:context, :observability, :trace_id]),
        fetch_path(resolved_input, [:request, :metadata, :trace_id]),
        fetch_path(resolved_input, [:trace_id])
      ]) || @diagnostic_trace_id

    tenant_id =
      first_present([
        fetch_path(resolved_input, [:context, :metadata, :tenant_id]),
        fetch_path(resolved_input, [:request, :metadata, :tenant_id]),
        fetch_path(resolved_input, [:trigger, :tenant_id]),
        fetch_path(resolved_input, [:tenant_id])
      ]) || @diagnostic_tenant_id

    installation_id =
      first_present([
        fetch_path(resolved_input, [:context, :metadata, :installation_id]),
        fetch_path(resolved_input, [:request, :metadata, :installation_id]),
        fetch_path(resolved_input, [:installation_id])
      ])

    diagnostics =
      %{}
      |> maybe_put_diagnostic(:trace_id, trace_id == @diagnostic_trace_id, "missing")
      |> maybe_put_diagnostic(:tenant_id, tenant_id == @diagnostic_tenant_id, "missing")
      |> Map.merge(input_resolution.diagnostics)

    %{
      trace_id: trace_id,
      tenant_id: tenant_id,
      installation_id: installation_id,
      diagnostics: diagnostics
    }
  end

  defp event_scope(scope, event_trace_id) do
    diagnostics =
      scope.diagnostics
      |> Map.delete("trace_id")
      |> maybe_put_diagnostic(
        :trace_id,
        event_trace_id == @diagnostic_trace_id,
        "missing"
      )

    %{scope | trace_id: event_trace_id, diagnostics: diagnostics}
  end

  defp envelope_staleness(scope, resolutions) do
    if map_size(scope.diagnostics) == 0 and Enum.all?(resolutions, &(&1.status == :live)) do
      :live
    else
      :diagnostic_only
    end
  end

  defp resolve_optional_json(nil, _payload_ref),
    do: %{payload: nil, diagnostics: %{}, status: :live}

  defp resolve_optional_json(payload, nil) when is_map(payload),
    do: %{payload: Contracts.dump_json_safe!(payload), diagnostics: %{}, status: :live}

  defp resolve_optional_json(payload, payload_ref) when is_map(payload) and is_map(payload_ref) do
    case ClaimCheck.resolve_json(payload, payload_ref) do
      {:ok, resolved} ->
        %{payload: Contracts.dump_json_safe!(resolved), diagnostics: %{}, status: :live}

      {:error, reason} ->
        %{
          payload: Contracts.dump_json_safe!(payload),
          diagnostics: %{"payload_resolution" => inspect(reason)},
          status: :diagnostic_only
        }
    end
  end

  defp normalize_event_types(nil), do: {:ok, MapSet.new(export_kinds())}

  defp normalize_event_types(event_types) when is_list(event_types) do
    normalized =
      Enum.reduce_while(event_types, {:ok, []}, fn
        value, {:ok, acc} when is_binary(value) ->
          if value in @export_kinds do
            {:cont, {:ok, [value | acc]}}
          else
            {:halt, {:error, :invalid_event_types}}
          end

        _value, _acc ->
          {:halt, {:error, :invalid_event_types}}
      end)

    case normalized do
      {:ok, values} -> {:ok, MapSet.new(Enum.reverse(values))}
      error -> error
    end
  end

  defp normalize_event_types(_event_types), do: {:error, :invalid_event_types}

  defp export_id(kind, durable_id) do
    "jido://v2/audit_export/#{URI.encode_www_form(kind)}/#{URI.encode_www_form(durable_id)}"
  end

  defp payload_with_diagnostics(kind, fact, diagnostics) do
    payload = %{kind => Contracts.dump_json_safe!(fact)}

    if map_size(diagnostics) == 0 do
      payload
    else
      Map.put(payload, "diagnostics", diagnostics)
    end
  end

  defp trace_id_from_events(events) do
    events
    |> Enum.find_value(fn event -> first_present([Contracts.get(event.trace, :trace_id)]) end)
  end

  defp fetch_path(map, path) when is_map(map) and is_list(path) do
    Enum.reduce_while(path, map, fn segment, acc ->
      fetch_path_segment(acc, segment)
    end)
  end

  defp fetch_path(_map, _path), do: nil

  defp fetch_path_segment(%{} = nested, segment) do
    case Contracts.get(nested, segment) do
      nil -> {:halt, nil}
      value -> {:cont, value}
    end
  end

  defp fetch_path_segment(_other, _segment), do: {:halt, nil}

  defp first_present(values) do
    Enum.find(values, &present_binary?/1)
  end

  defp present_binary?(value), do: is_binary(value) and value != ""

  defp maybe_put_diagnostic(diagnostics, _field, false, _message), do: diagnostics

  defp maybe_put_diagnostic(diagnostics, field, true, message) do
    Map.put(diagnostics, Atom.to_string(field), message)
  end
end
