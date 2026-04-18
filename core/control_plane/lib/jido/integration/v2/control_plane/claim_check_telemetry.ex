defmodule Jido.Integration.V2.ControlPlane.ClaimCheckTelemetry do
  @moduledoc """
  Package-owned `:telemetry` surface for claim-check staging and cleanup.
  """

  alias Jido.Integration.V2.Redaction

  @type event_name ::
          :stage
          | :stage_failure
          | :orphaned_staged_payload
          | :blob_gc_deleted
          | :blob_gc_skipped_live_reference

  @events %{
    stage: [:jido, :integration, :claim_check, :stage],
    stage_failure: [:jido, :integration, :claim_check, :stage_failure],
    orphaned_staged_payload: [:jido, :integration, :claim_check, :orphaned_staged_payload],
    blob_gc_deleted: [:jido, :integration, :claim_check, :blob_gc_deleted],
    blob_gc_skipped_live_reference: [
      :jido,
      :integration,
      :claim_check,
      :blob_gc_skipped_live_reference
    ]
  }

  @spec event(event_name()) :: [atom(), ...]
  def event(name), do: Map.fetch!(@events, name)

  @spec events() :: %{required(event_name()) => [atom(), ...]}
  def events, do: @events

  @spec stage(map(), map(), keyword()) :: :ok
  def stage(payload_ref, metadata, opts \\ []) do
    emit(
      :stage,
      measurements(
        payload_bytes(payload_ref, metadata),
        latency_ms: Keyword.get(opts, :latency_ms)
      ),
      metadata(payload_ref, metadata, Keyword.take(opts, [:source_component, :store_backend]))
    )
  end

  @spec stage_failure(map(), map(), term(), keyword()) :: :ok
  def stage_failure(payload_ref, metadata, reason, opts \\ []) do
    emit(
      :stage_failure,
      measurements(
        payload_bytes(payload_ref, metadata),
        latency_ms: Keyword.get(opts, :latency_ms)
      ),
      metadata(
        payload_ref,
        metadata,
        Keyword.take(opts, [:source_component, :store_backend])
        |> Keyword.put(:reason, normalize_reason(reason))
      )
    )
  end

  @spec orphaned_staged_payload(map(), map(), keyword()) :: :ok
  def orphaned_staged_payload(payload_ref, metadata, opts \\ []) do
    emit(
      :orphaned_staged_payload,
      measurements(payload_bytes(payload_ref, metadata)),
      metadata(payload_ref, metadata, Keyword.take(opts, [:source_component, :store_backend]))
    )
  end

  @spec blob_gc_deleted(map(), map(), keyword()) :: :ok
  def blob_gc_deleted(payload_ref, metadata, opts \\ []) do
    emit(
      :blob_gc_deleted,
      measurements(payload_bytes(payload_ref, metadata)),
      metadata(payload_ref, metadata, Keyword.take(opts, [:source_component, :store_backend]))
    )
  end

  @spec blob_gc_skipped_live_reference(map(), map(), keyword()) :: :ok
  def blob_gc_skipped_live_reference(payload_ref, metadata, opts \\ []) do
    emit(
      :blob_gc_skipped_live_reference,
      measurements(payload_bytes(payload_ref, metadata)),
      metadata(
        payload_ref,
        metadata,
        Keyword.take(opts, [:source_component, :store_backend])
        |> Keyword.put(
          :live_reference_count,
          Keyword.get(opts, :live_reference_count, 0)
        )
      )
    )
  end

  defp emit(name, measurements, metadata) do
    :telemetry.execute(event(name), measurements, Redaction.redact(metadata))
  end

  defp measurements(payload_bytes, opts \\ []) do
    %{count: 1, payload_bytes: payload_bytes}
    |> maybe_put(:latency_ms, normalize_non_negative_integer(Keyword.get(opts, :latency_ms)))
  end

  defp metadata(payload_ref, metadata, opts) do
    %{
      trace_id: fetch_value(metadata, :trace_id),
      payload_ref: normalize_payload_ref(payload_ref),
      payload_kind: fetch_value(metadata, :payload_kind),
      redaction_class: fetch_value(metadata, :redaction_class),
      content_type: fetch_value(metadata, :content_type),
      source_component: Keyword.get(opts, :source_component),
      store_backend: Keyword.get(opts, :store_backend),
      reason: Keyword.get(opts, :reason),
      live_reference_count: normalize_non_negative_integer(Keyword.get(opts, :live_reference_count))
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp payload_bytes(payload_ref, metadata) do
    fetch_value(payload_ref, :size_bytes) || fetch_value(metadata, :size_bytes) || 0
  end

  defp normalize_payload_ref(payload_ref) when is_map(payload_ref) do
    %{
      store: fetch_value(payload_ref, :store),
      key: fetch_value(payload_ref, :key),
      checksum: fetch_value(payload_ref, :checksum),
      size_bytes: fetch_value(payload_ref, :size_bytes)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_payload_ref(_payload_ref), do: %{}

  defp fetch_value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp fetch_value(_other, _key), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_reason(reason) when is_binary(reason), do: reason
  defp normalize_reason(reason), do: inspect(reason)

  defp normalize_non_negative_integer(nil), do: nil
  defp normalize_non_negative_integer(value) when is_integer(value) and value >= 0, do: value
  defp normalize_non_negative_integer(value) when is_integer(value), do: 0
  defp normalize_non_negative_integer(_value), do: nil
end
