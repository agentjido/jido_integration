defmodule Jido.Integration.V2.ArtifactRef do
  @moduledoc """
  Stable public reference to a run artifact.

  Artifacts are references by default. The contract stores integrity metadata,
  a resolvable `payload_ref`, and retention/redaction posture without carrying
  the artifact body inline.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

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
  @artifact_types [:event_log, :stdout, :stderr, :diff, :tarball, :tool_output, :log, :custom]
  @transport_modes [:inline, :chunked, :object_store]
  @redaction_statuses [:clear, :redacted, :withheld]

  @schema Zoi.struct(
            __MODULE__,
            %{
              artifact_id: Contracts.non_empty_string_schema("artifact_ref.artifact_id"),
              run_id: Contracts.non_empty_string_schema("artifact_ref.run_id"),
              attempt_id: Contracts.non_empty_string_schema("artifact_ref.attempt_id"),
              artifact_type:
                Contracts.enumish_schema(@artifact_types, "artifact_ref.artifact_type"),
              transport_mode:
                Contracts.enumish_schema(@transport_modes, "artifact_ref.transport_mode"),
              checksum: Zoi.string(),
              size_bytes: Zoi.integer() |> Zoi.min(0),
              payload_ref: Contracts.payload_ref_schema("artifact_ref.payload_ref"),
              retention_class: Zoi.any(),
              redaction_status:
                Contracts.enumish_schema(@redaction_statuses, "artifact_ref.redaction_status"),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = artifact_ref), do: normalize(artifact_ref)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = attrs |> Map.new() |> prepare_attrs()

    case Schema.new(__MODULE__, @schema, attrs) do
      {:ok, artifact_ref} -> normalize(artifact_ref)
      {:error, %ArgumentError{} = error} -> {:error, error}
    end
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = artifact_ref) do
    case normalize(artifact_ref) do
      {:ok, artifact_ref} -> artifact_ref
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, artifact_ref} -> artifact_ref
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  defp prepare_attrs(attrs) do
    Map.put(attrs, :metadata, normalize_metadata(attrs))
  end

  defp normalize(%__MODULE__{} = artifact_ref) do
    checksum = Contracts.validate_checksum!(artifact_ref.checksum)
    payload_ref = Contracts.normalize_payload_ref!(artifact_ref.payload_ref)
    retention_class = normalize_retention_class!(artifact_ref.retention_class)
    _attempt_number = Contracts.attempt_from_id!(artifact_ref.run_id, artifact_ref.attempt_id)

    cond do
      payload_ref.checksum != checksum ->
        {:error, ArgumentError.exception("artifact checksum must match payload_ref.checksum")}

      payload_ref.size_bytes != artifact_ref.size_bytes ->
        {:error, ArgumentError.exception("artifact size_bytes must match payload_ref.size_bytes")}

      true ->
        {:ok,
         %__MODULE__{
           artifact_ref
           | checksum: checksum,
             payload_ref: payload_ref,
             retention_class: retention_class
         }}
    end
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
