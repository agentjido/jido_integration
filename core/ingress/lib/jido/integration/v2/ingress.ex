defmodule Jido.Integration.V2.Ingress do
  @moduledoc """
  Normalizes webhook and polling triggers into durable control-plane truth.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.Ingress.Definition
  alias Jido.Integration.V2.Ingress.PlugSecureCompare
  alias Jido.Integration.V2.Ingress.Serialization
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord
  alias Jido.Signal

  @type admission_result ::
          {:ok, %{status: :accepted | :duplicate, trigger: TriggerRecord.t(), run: map()}}
          | {:error, %{reason: term(), trigger: TriggerRecord.t()}}

  @spec admit_webhook(map(), Definition.t()) :: admission_result()
  def admit_webhook(request, %Definition{source: :webhook} = definition) do
    with {:ok, trigger} <- build_trigger_record(request, definition, webhook_payload(request)),
         :ok <- verify_signature(request, definition, trigger),
         :ok <- validate_trigger_payload(trigger, definition),
         {:ok, result} <-
           admit_trigger(trigger, dedupe_ttl_seconds: definition.dedupe_ttl_seconds) do
      {:ok, result}
    else
      {:error, reason, %TriggerRecord{} = trigger} ->
        reject(trigger, reason)

      {:error, reason} ->
        reject(build_rejection_trigger(request, definition, webhook_payload(request)), reason)
    end
  end

  @spec admit_poll(map(), Definition.t()) :: admission_result()
  def admit_poll(request, %Definition{source: :poll} = definition) do
    payload = poll_payload(request)

    with {:ok, trigger} <- build_trigger_record(request, definition, payload),
         {:ok, checkpoint} <- build_checkpoint(request, definition, trigger),
         :ok <- validate_trigger_payload(trigger, definition),
         {:ok, result} <-
           admit_trigger(trigger,
             checkpoint: checkpoint,
             dedupe_ttl_seconds: definition.dedupe_ttl_seconds
           ) do
      {:ok, result}
    else
      {:error, reason, %TriggerRecord{} = trigger} ->
        reject(trigger, reason)

      {:error, reason} ->
        reject(build_rejection_trigger(request, definition, payload), reason)
    end
  end

  defp build_trigger_record(request, definition, payload) do
    with {:ok, tenant_id} <- fetch_required_string(request, :tenant_id),
         {:ok, signal} <- build_signal(request, definition, payload),
         dedupe_key <- dedupe_key(request, payload) do
      {:ok,
       TriggerRecord.new!(%{
         source: definition.source,
         connector_id: definition.connector_id,
         trigger_id: definition.trigger_id,
         capability_id: definition.capability_id,
         tenant_id: tenant_id,
         external_id: Map.get(request, :external_id),
         dedupe_key: dedupe_key,
         partition_key: Map.get(request, :partition_key),
         payload: payload,
         signal: signal
       })}
    else
      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error in [ArgumentError, KeyError] ->
      {:error, {:invalid_trigger, Exception.message(error)}}
  end

  defp build_rejection_trigger(request, definition, payload) do
    tenant_id = Map.get(request, :tenant_id, "unknown")

    signal =
      case build_signal(request, definition, payload) do
        {:ok, built_signal} -> built_signal
        {:error, _reason} -> %{}
      end

    TriggerRecord.new!(%{
      source: definition.source,
      connector_id: definition.connector_id,
      trigger_id: definition.trigger_id,
      capability_id: definition.capability_id,
      tenant_id: tenant_id,
      external_id: Map.get(request, :external_id),
      dedupe_key: dedupe_key(request, payload),
      partition_key: Map.get(request, :partition_key),
      payload: payload,
      signal: signal
    })
  end

  defp build_checkpoint(request, definition, %TriggerRecord{} = trigger) do
    with {:ok, tenant_id} <- fetch_required_string(request, :tenant_id),
         {:ok, partition_key} <- fetch_required_string(request, :partition_key),
         {:ok, cursor} <- fetch_required_string(request, :cursor) do
      {:ok,
       TriggerCheckpoint.new!(%{
         tenant_id: tenant_id,
         connector_id: definition.connector_id,
         trigger_id: definition.trigger_id,
         partition_key: partition_key,
         cursor: cursor,
         last_event_id: Map.get(request, :last_event_id),
         last_event_time: Map.get(request, :last_event_time)
       })}
    else
      {:error, reason} ->
        {:error, reason, trigger}
    end
  rescue
    error in [ArgumentError, KeyError] ->
      {:error, {:invalid_trigger, Exception.message(error)}, trigger}
  end

  defp build_signal(request, definition, payload) do
    {:ok, _} = Application.ensure_all_started(:jido_signal)
    dedupe_key = dedupe_key(request, payload)

    case Signal.new(definition.signal_type, payload,
           source: definition.signal_source,
           subject: signal_subject(request, definition),
           extensions: %{
             tenant_id: Map.get(request, :tenant_id),
             connector_id: definition.connector_id,
             trigger_id: definition.trigger_id,
             dedupe_key: dedupe_key,
             partition_key: Map.get(request, :partition_key),
             external_id: Map.get(request, :external_id)
           }
         ) do
      {:ok, signal} ->
        {:ok, signal |> Map.from_struct() |> Serialization.normalize()}

      {:error, reason} ->
        {:error, {:invalid_trigger, reason}}
    end
  end

  defp validate_trigger_payload(%TriggerRecord{payload: payload} = trigger, definition) do
    case validate_payload(payload, definition) do
      :ok -> :ok
      {:error, reason} -> {:error, reason, trigger}
    end
  end

  defp validate_payload(_payload, %Definition{validator: nil}), do: :ok

  defp validate_payload(payload, %Definition{validator: validator}) do
    case validator.(payload) do
      :ok -> :ok
      {:error, reason} -> {:error, {:invalid_trigger, reason}}
      other -> {:error, {:invalid_trigger, {:unexpected_validator_result, other}}}
    end
  end

  defp verify_signature(_request, %Definition{verification: nil}, _trigger), do: :ok

  defp verify_signature(
         request,
         %Definition{verification: verification},
         %TriggerRecord{} = trigger
       ) do
    signature =
      request
      |> Map.get(:headers, %{})
      |> get_header(verification.signature_header)

    raw_body = Map.get(request, :raw_body, "")

    expected =
      "sha256=" <>
        Base.encode16(
          :crypto.mac(:hmac, verification.algorithm, verification.secret, raw_body),
          case: :lower
        )

    if PlugSecureCompare.secure_compare(signature || "", expected) do
      :ok
    else
      {:error, :signature_invalid, trigger}
    end
  end

  defp admit_trigger(%TriggerRecord{} = trigger, opts) do
    case ControlPlane.admit_trigger(trigger, opts) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason, trigger}
    end
  end

  defp reject(%TriggerRecord{} = trigger, reason) do
    case ControlPlane.record_rejected_trigger(trigger, reason) do
      {:ok, rejected_trigger} ->
        {:error, %{reason: reason, trigger: rejected_trigger}}

      {:error, record_error} ->
        {:error, %{reason: {:rejection_record_failed, reason, record_error}, trigger: trigger}}
    end
  end

  defp fetch_required_string(map, key) do
    case Contracts.get(map, key) do
      value when is_binary(value) ->
        if byte_size(String.trim(value)) > 0 do
          {:ok, value}
        else
          {:error, {:invalid_trigger, {:missing_field, key}}}
        end

      _ ->
        {:error, {:invalid_trigger, {:missing_field, key}}}
    end
  end

  defp webhook_payload(request) do
    normalize_payload(Map.get(request, :body, %{}))
  end

  defp poll_payload(request) do
    normalize_payload(Map.get(request, :event, %{}))
  end

  defp normalize_payload(payload) when is_map(payload), do: payload
  defp normalize_payload(payload), do: %{"value" => payload}

  defp dedupe_key(request, payload) do
    case Map.get(request, :external_id) do
      external_id when is_binary(external_id) and byte_size(external_id) > 0 ->
        external_id

      _ ->
        payload
        |> inspect()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)
    end
  end

  defp signal_subject(request, definition) do
    [Map.get(request, :tenant_id), definition.trigger_id, Map.get(request, :external_id)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp get_header(headers, key) when is_map(headers) do
    Map.get(headers, key) || Map.get(headers, String.downcase(key))
  end

  defmodule Serialization do
    @moduledoc false

    def normalize(%DateTime{} = value), do: DateTime.to_iso8601(value)

    def normalize(%_{} = struct) do
      struct
      |> Map.from_struct()
      |> normalize()
    end

    def normalize(map) when is_map(map) do
      Enum.into(map, %{}, fn {key, value} -> {to_string(key), normalize(value)} end)
    end

    def normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
    def normalize(value), do: value
  end

  defmodule PlugSecureCompare do
    @moduledoc false

    import Bitwise

    @spec secure_compare(binary(), binary()) :: boolean()
    def secure_compare(left, right) when byte_size(left) == byte_size(right) do
      left
      |> :binary.bin_to_list()
      |> Enum.zip(:binary.bin_to_list(right))
      |> Enum.reduce(0, fn {left_byte, right_byte}, acc ->
        acc ||| bxor(left_byte, right_byte)
      end)
      |> Kernel.==(0)
    end

    def secure_compare(_left, _right), do: false
  end
end
