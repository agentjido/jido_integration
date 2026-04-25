defmodule Jido.Integration.V2.AsmRuntimeBridge.Normalizer do
  @moduledoc false

  alias ASM.{Error, Event, Result}
  alias Jido.Integration.V2.Redaction

  alias Jido.RuntimeControl.{
    ExecutionEvent,
    ExecutionResult,
    SessionHandle
  }

  @spec canonical_provider(atom() | nil) :: atom() | nil
  def canonical_provider(:codex_exec), do: :codex
  def canonical_provider(provider) when is_atom(provider), do: provider
  def canonical_provider(_other), do: nil

  @spec to_execution_event(Event.t(), SessionHandle.t()) :: ExecutionEvent.t()
  def to_execution_event(%Event{} = event, %SessionHandle{} = session) do
    ExecutionEvent.new!(%{
      event_id: event.id,
      type: event.kind,
      session_id: session.session_id,
      run_id: event.run_id,
      runtime_id: session.runtime_id,
      provider: session.provider || canonical_provider(event.provider),
      provider_session_id: provider_session_id(event),
      provider_turn_id: provider_turn_id(event),
      provider_request_id: provider_request_id(event),
      provider_item_id: provider_item_id(event),
      provider_tool_call_id: provider_tool_call_id(event),
      provider_message_id: provider_message_id(event),
      tool_name: tool_name(event),
      approval_id: approval_id(event),
      sequence: event.sequence,
      timestamp: DateTime.to_iso8601(event.timestamp),
      status: event_status(event.kind),
      payload: normalize_payload(event.kind, event.payload),
      raw: safe_raw_event(event),
      metadata:
        %{}
        |> maybe_put("correlation_id", event.correlation_id)
        |> maybe_put("causation_id", event.causation_id)
        |> maybe_put("provider_session_id", provider_session_id(event))
        |> maybe_put("provider_turn_id", provider_turn_id(event))
        |> maybe_put("provider_request_id", provider_request_id(event))
        |> maybe_put("provider_item_id", provider_item_id(event))
        |> maybe_put("provider_tool_call_id", provider_tool_call_id(event))
        |> maybe_put("provider_message_id", provider_message_id(event))
        |> maybe_put("tool_name", tool_name(event))
        |> maybe_put("approval_id", approval_id(event))
        |> maybe_put("boundary", boundary_metadata(session))
    })
  end

  @spec to_execution_result(Result.t(), SessionHandle.t()) :: ExecutionResult.t()
  def to_execution_result(%Result{} = result, %SessionHandle{} = session) do
    metadata =
      result.metadata
      |> normalize()
      |> default_map()
      |> maybe_put("provider_session_id", result.session_id_from_cli)
      |> maybe_put("provider_turn_id", metadata_value(result.metadata, :provider_turn_id))
      |> maybe_put("boundary", boundary_metadata(session))

    ExecutionResult.new!(%{
      run_id: result.run_id,
      session_id: session.session_id,
      runtime_id: session.runtime_id,
      provider: session.provider,
      provider_session_id: result.session_id_from_cli,
      provider_turn_id: metadata_value(result.metadata, :provider_turn_id),
      status: result_status(result),
      text: result.text,
      messages: normalize(result.messages || []),
      cost: result.cost |> normalize() |> default_map(),
      error: normalize_error(result.error),
      duration_ms: result.duration_ms,
      stop_reason: normalize_reason(result.stop_reason),
      metadata: metadata
    })
  end

  @spec normalize(term()) :: term()
  def normalize(nil), do: nil
  def normalize(value) when is_boolean(value), do: value
  def normalize(value) when is_integer(value), do: value
  def normalize(value) when is_float(value), do: value
  def normalize(value) when is_binary(value), do: value
  def normalize(value) when is_atom(value), do: Atom.to_string(value)
  def normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)

  def normalize(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize()
  end

  def normalize(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {normalize_key(key), normalize(value)} end)
  end

  def normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  def normalize(other), do: other

  defp normalize_payload(_kind, nil), do: %{}

  defp normalize_payload(:error, payload) do
    payload
    |> normalize()
    |> default_payload_map()
    |> maybe_put_error_kind()
  end

  defp normalize_payload(kind, %{__struct__: struct} = payload)
       when kind in [
              :host_tool_requested,
              :host_tool_completed,
              :host_tool_failed,
              :host_tool_denied
            ] and struct in [ASM.HostTool.Request, ASM.HostTool.Response] do
    payload
    |> Map.from_struct()
    |> Map.drop([:raw])
    |> normalize()
    |> Redaction.redact()
    |> default_payload_map()
  end

  defp normalize_payload(_kind, payload) do
    payload
    |> normalize()
    |> Redaction.redact()
    |> default_payload_map()
  end

  defp normalize_error(nil), do: nil

  defp normalize_error(%Error{} = error) do
    error
    |> Map.from_struct()
    |> normalize()
    |> default_map()
  end

  defp normalize_error(other) do
    other
    |> normalize()
    |> Redaction.redact()
    |> default_payload_map()
  end

  defp safe_raw_event(%Event{} = event) do
    %{
      kind: event.kind,
      provider: event.provider,
      provider_session_id: provider_session_id(event),
      provider_turn_id: provider_turn_id(event),
      provider_request_id: provider_request_id(event),
      provider_item_id: provider_item_id(event),
      provider_tool_call_id: provider_tool_call_id(event),
      provider_message_id: provider_message_id(event),
      tool_name: tool_name(event),
      approval_id: approval_id(event),
      metadata: event.metadata,
      payload: normalize_payload(event.kind, event.payload)
    }
    |> normalize()
    |> Redaction.redact()
  end

  defp provider_session_id(%Event{} = event) do
    id_to_string(event.provider_session_id || payload_value(event.payload, :provider_session_id))
  end

  defp provider_turn_id(%Event{} = event) do
    id_to_string(
      metadata_value(event.metadata, :provider_turn_id) ||
        payload_value(event.payload, :provider_turn_id)
    )
  end

  defp provider_request_id(%Event{} = event) do
    id_to_string(
      metadata_value(event.metadata, :provider_request_id) ||
        metadata_value(event.metadata, :codex_request_id) ||
        payload_value(event.payload, :provider_request_id) ||
        payload_value(event.payload, :request_id) ||
        host_tool_request_id(event)
    )
  end

  defp provider_item_id(%Event{} = event) do
    id_to_string(
      metadata_value(event.metadata, :provider_item_id) ||
        metadata_value(event.metadata, :item_id) ||
        payload_value(event.payload, :provider_item_id) ||
        payload_value(event.payload, :item_id)
    )
  end

  defp provider_tool_call_id(%Event{} = event) do
    id_to_string(
      metadata_value(event.metadata, :provider_tool_call_id) ||
        metadata_value(event.metadata, :tool_call_id) ||
        metadata_value(event.metadata, :call_id) ||
        payload_value(event.payload, :provider_tool_call_id) ||
        payload_value(event.payload, :tool_call_id) ||
        payload_value(event.payload, :call_id)
    )
  end

  defp provider_message_id(%Event{} = event) do
    id_to_string(
      metadata_value(event.metadata, :provider_message_id) ||
        metadata_value(event.metadata, :message_id) ||
        payload_value(event.payload, :provider_message_id) ||
        payload_value(event.payload, :message_id)
    )
  end

  defp tool_name(%Event{} = event) do
    metadata_value(event.metadata, :tool_name) || payload_value(event.payload, :tool_name)
  end

  defp approval_id(%Event{} = event) do
    id_to_string(
      payload_value(event.payload, :approval_id) || metadata_value(event.metadata, :approval_id)
    )
  end

  defp metadata_value(%{} = map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp metadata_value(_map, _key), do: nil

  defp payload_value(%{} = map, key), do: metadata_value(map, key)
  defp payload_value(%_{} = struct, key), do: struct |> Map.from_struct() |> metadata_value(key)
  defp payload_value(_payload, _key), do: nil

  defp host_tool_request_id(%Event{kind: kind, payload: payload})
       when kind in [
              :host_tool_requested,
              :host_tool_completed,
              :host_tool_failed,
              :host_tool_denied
            ] do
    payload_value(payload, :id)
  end

  defp host_tool_request_id(_event), do: nil

  defp id_to_string(nil), do: nil
  defp id_to_string(value) when is_binary(value), do: value
  defp id_to_string(value) when is_integer(value), do: Integer.to_string(value)
  defp id_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp id_to_string(value), do: inspect(value)

  defp normalize_reason(nil), do: nil
  defp normalize_reason(reason) when is_binary(reason), do: reason
  defp normalize_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_reason(reason), do: inspect(reason)

  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: inspect(key)

  defp result_status(%Result{error: nil}), do: :completed
  defp result_status(%Result{error: %Error{kind: :user_cancelled}}), do: :cancelled
  defp result_status(%Result{}), do: :failed

  defp event_status(:run_started), do: :running
  defp event_status(:result), do: :completed
  defp event_status(:run_completed), do: :completed
  defp event_status(:error), do: :failed
  defp event_status(_kind), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_error_kind(%{"code" => code} = payload) when is_binary(code) and code != "" do
    Map.put_new(payload, "kind", code)
  end

  defp maybe_put_error_kind(payload), do: payload

  defp default_payload_map(%{} = value), do: value
  defp default_payload_map(other), do: %{"value" => other}

  defp default_map(%{} = value), do: value
  defp default_map(_other), do: %{}

  defp boundary_metadata(%SessionHandle{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "boundary") || Map.get(metadata, :boundary)
  end

  defp boundary_metadata(_session), do: nil
end
