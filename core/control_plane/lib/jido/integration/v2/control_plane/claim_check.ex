defmodule Jido.Integration.V2.ControlPlane.ClaimCheck do
  @moduledoc false

  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane.ClaimCheckTelemetry
  alias Jido.Integration.V2.ControlPlane.Stores
  alias Jido.Integration.V2.Redaction

  @default_inline_threshold_bytes 64 * 1024
  @default_ttl_s 7 * 24 * 60 * 60
  @default_store "claim_check_hot"
  @claim_check_key "__claim_check__"

  @spec prepare_json(map(), keyword()) ::
          {:ok,
           %{
             payload: map(),
             payload_ref: Contracts.payload_ref() | nil,
             size_bytes: non_neg_integer(),
             claim_checked?: boolean()
           }}
          | {:error, term()}
  def prepare_json(payload, opts \\ [])

  def prepare_json(payload, opts) when is_map(payload) do
    started_at_ms = System.monotonic_time(:millisecond)

    normalized =
      payload
      |> Redaction.redact()
      |> Contracts.dump_json_safe!()

    encoded = CanonicalJson.encode!(normalized)
    size_bytes = byte_size(encoded)
    threshold = Keyword.get(opts, :inline_threshold_bytes, @default_inline_threshold_bytes)

    if size_bytes <= threshold do
      {:ok,
       %{payload: normalized, payload_ref: nil, size_bytes: size_bytes, claim_checked?: false}}
    else
      payload_ref = payload_ref_for(normalized, size_bytes, opts)
      stage_metadata = stage_metadata(opts, size_bytes)

      case stage_blob(payload_ref, encoded, opts) do
        :ok ->
          ClaimCheckTelemetry.stage(
            payload_ref,
            stage_metadata,
            latency_ms: elapsed_ms(started_at_ms),
            source_component: :claim_check,
            store_backend: payload_ref.store
          )

          {:ok,
           %{
             payload: claim_check_summary(normalized, payload_ref, size_bytes, threshold, opts),
             payload_ref: payload_ref,
             size_bytes: size_bytes,
             claim_checked?: true
           }}

        {:error, reason} = error ->
          ClaimCheckTelemetry.stage_failure(
            payload_ref,
            stage_metadata,
            reason,
            latency_ms: elapsed_ms(started_at_ms),
            source_component: :claim_check,
            store_backend: payload_ref.store
          )

          error
      end
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  def prepare_json(payload, _opts) do
    {:error,
     ArgumentError.exception("claim-check payload must be a map, got: #{inspect(payload)}")}
  end

  @spec resolve_json(map(), Contracts.payload_ref() | nil) :: {:ok, map()} | {:error, term()}
  def resolve_json(payload, nil) when is_map(payload), do: {:ok, payload}

  def resolve_json(payload, payload_ref) when is_map(payload) and is_map(payload_ref) do
    case Stores.claim_check_store().fetch_blob(payload_ref) do
      {:ok, encoded} ->
        {:ok, Jason.decode!(encoded)}

      :error ->
        {:error, :claim_check_missing}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def resolve_json(payload, _payload_ref) when is_map(payload) do
    {:ok, payload}
  end

  @spec claim_checked?(map()) :: boolean()
  def claim_checked?(payload) when is_map(payload), do: is_map(Map.get(payload, @claim_check_key))
  def claim_checked?(_payload), do: false

  @spec metadata_key() :: String.t()
  def metadata_key, do: @claim_check_key

  defp stage_blob(payload_ref, encoded, opts) do
    Stores.claim_check_store().stage_blob(
      payload_ref,
      encoded,
      %{
        content_type: Keyword.get(opts, :content_type, "application/json"),
        redaction_class: Keyword.get(opts, :redaction_class, "redacted"),
        payload_kind: Keyword.get(opts, :payload_kind) |> maybe_stringify(),
        trace_id: Keyword.get(opts, :trace_id)
      }
    )
  end

  defp payload_ref_for(normalized, size_bytes, opts) do
    checksum = CanonicalJson.checksum!(normalized)
    digest = String.replace_prefix(checksum, "sha256:", "")

    %{
      store: Keyword.get(opts, :store, @default_store),
      key: "sha256/#{digest}",
      ttl_s: Keyword.get(opts, :ttl_s, @default_ttl_s),
      access_control: Keyword.get(opts, :access_control, :run_scoped),
      checksum: checksum,
      size_bytes: size_bytes
    }
  end

  defp claim_check_summary(normalized, payload_ref, size_bytes, threshold, opts) do
    metadata = %{
      "store" => payload_ref.store,
      "key" => payload_ref.key,
      "checksum" => payload_ref.checksum,
      "size_bytes" => size_bytes,
      "content_type" => Keyword.get(opts, :content_type, "application/json"),
      "redaction_class" => Keyword.get(opts, :redaction_class, "redacted"),
      "inline_threshold_bytes" => threshold,
      "payload_kind" => maybe_stringify(Keyword.get(opts, :payload_kind)),
      "trace_id" => Keyword.get(opts, :trace_id),
      "preview" => preview(normalized)
    }

    normalized
    |> Map.take(["contract_version", "schema_version", "status", "type"])
    |> Map.put(@claim_check_key, metadata)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp preview(%{} = payload) do
    payload
    |> Map.take(["contract_version", "schema_version", "status", "type"])
    |> Map.merge(%{
      "shape" => "map",
      "top_level_keys" => payload |> Map.keys() |> Enum.sort() |> Enum.take(24)
    })
  end

  defp preview(payload) when is_list(payload) do
    %{"shape" => "list", "length" => length(payload)}
  end

  defp preview(_payload) do
    %{"shape" => "scalar"}
  end

  defp maybe_stringify(nil), do: nil
  defp maybe_stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp maybe_stringify(value), do: to_string(value)

  defp stage_metadata(opts, size_bytes) do
    %{
      trace_id: Keyword.get(opts, :trace_id),
      payload_kind: Keyword.get(opts, :payload_kind) |> maybe_stringify(),
      redaction_class: Keyword.get(opts, :redaction_class, "redacted"),
      content_type: Keyword.get(opts, :content_type, "application/json"),
      size_bytes: size_bytes
    }
  end

  defp elapsed_ms(started_at_ms) do
    System.monotonic_time(:millisecond) - started_at_ms
  end
end
