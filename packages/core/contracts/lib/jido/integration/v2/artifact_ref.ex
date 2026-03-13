defmodule Jido.Integration.V2.ArtifactRef do
  @moduledoc """
  Stable public reference to a run artifact.

  Artifacts are references by default. The contract stores integrity metadata,
  a resolvable `payload_ref`, and retention/redaction posture without carrying
  the artifact body inline.
  """

  alias Jido.Integration.V2.Contracts

  @known_keys [
    :artifact_id,
    :run_id,
    :attempt_id,
    :artifact_type,
    :transport_mode,
    :checksum,
    :size_bytes,
    :payload_ref,
    :retention_class,
    :redaction_status,
    :metadata
  ]

  @enforce_keys [
    :artifact_id,
    :run_id,
    :attempt_id,
    :artifact_type,
    :transport_mode,
    :checksum,
    :size_bytes,
    :payload_ref,
    :retention_class,
    :redaction_status
  ]
  defstruct [
    :artifact_id,
    :run_id,
    :attempt_id,
    :artifact_type,
    :transport_mode,
    :checksum,
    :size_bytes,
    :payload_ref,
    :retention_class,
    :redaction_status,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          artifact_id: String.t(),
          run_id: String.t(),
          attempt_id: String.t(),
          artifact_type: Contracts.artifact_type(),
          transport_mode: Contracts.transport_mode(),
          checksum: Contracts.checksum(),
          size_bytes: non_neg_integer(),
          payload_ref: Contracts.payload_ref(),
          retention_class: String.t(),
          redaction_status: :clear | :redacted | :withheld,
          metadata: map()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    run_id = Contracts.validate_non_empty_string!(Contracts.fetch!(attrs, :run_id), "run_id")

    attempt_id =
      Contracts.validate_non_empty_string!(Contracts.fetch!(attrs, :attempt_id), "attempt_id")

    _attempt_number = Contracts.attempt_from_id!(run_id, attempt_id)

    checksum = Contracts.validate_checksum!(Contracts.fetch!(attrs, :checksum))
    size_bytes = normalize_size_bytes!(Contracts.fetch!(attrs, :size_bytes))
    payload_ref = Contracts.normalize_payload_ref!(Contracts.fetch!(attrs, :payload_ref))
    retention_class = normalize_retention_class!(Contracts.fetch!(attrs, :retention_class))
    metadata = normalize_metadata(attrs)
    redaction_status = validate_redaction_status!(Contracts.fetch!(attrs, :redaction_status))

    if payload_ref.checksum != checksum do
      raise ArgumentError, "artifact checksum must match payload_ref.checksum"
    end

    if payload_ref.size_bytes != size_bytes do
      raise ArgumentError, "artifact size_bytes must match payload_ref.size_bytes"
    end

    struct!(__MODULE__, %{
      artifact_id:
        Contracts.validate_non_empty_string!(Contracts.fetch!(attrs, :artifact_id), "artifact_id"),
      run_id: run_id,
      attempt_id: attempt_id,
      artifact_type: Contracts.validate_artifact_type!(Contracts.fetch!(attrs, :artifact_type)),
      transport_mode:
        Contracts.validate_transport_mode!(Contracts.fetch!(attrs, :transport_mode)),
      checksum: checksum,
      size_bytes: size_bytes,
      payload_ref: payload_ref,
      retention_class: retention_class,
      redaction_status: redaction_status,
      metadata: metadata
    })
  end

  defp normalize_metadata(attrs) do
    metadata =
      case Contracts.get(attrs, :metadata, %{}) do
        value when is_map(value) -> value
        value -> raise ArgumentError, "artifact metadata must be a map, got: #{inspect(value)}"
      end

    attrs
    |> collect_unknown_fields(@known_keys)
    |> Map.merge(metadata)
  end

  defp normalize_retention_class!(retention_class) when is_atom(retention_class),
    do: Atom.to_string(retention_class)

  defp normalize_retention_class!(retention_class),
    do: Contracts.validate_non_empty_string!(retention_class, "retention_class")

  defp validate_redaction_status!(redaction_status)
       when redaction_status in [:clear, :redacted, :withheld],
       do: redaction_status

  defp validate_redaction_status!(redaction_status) when is_binary(redaction_status) do
    case Enum.find([:clear, :redacted, :withheld], &(Atom.to_string(&1) == redaction_status)) do
      nil -> raise ArgumentError, "invalid redaction_status: #{inspect(redaction_status)}"
      value -> value
    end
  end

  defp validate_redaction_status!(redaction_status) do
    raise ArgumentError, "invalid redaction_status: #{inspect(redaction_status)}"
  end

  defp normalize_size_bytes!(size_bytes) when is_integer(size_bytes) and size_bytes >= 0,
    do: size_bytes

  defp normalize_size_bytes!(size_bytes) do
    raise ArgumentError, "size_bytes must be a non-negative integer, got: #{inspect(size_bytes)}"
  end

  defp collect_unknown_fields(attrs, known_keys) do
    known_string_keys = Enum.map(known_keys, &Atom.to_string/1)

    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      known_variants =
        case key do
          atom when is_atom(atom) -> [atom, Atom.to_string(atom)]
          binary when is_binary(binary) -> [binary]
        end

      if Enum.any?(known_variants, &(&1 in known_keys or &1 in known_string_keys)) do
        acc
      else
        Map.put(acc, key, value)
      end
    end)
  end
end
