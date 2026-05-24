defmodule Jido.Integration.ModelInvocation.StreamFragment do
  @moduledoc """
  Ref-only streaming receipt fragment.
  """

  alias Jido.Integration.ModelInvocation.{Canonical, Validation}
  alias Jido.Integration.V2.Contracts

  @schema_version "jido.model_invocation.stream_fragment.v1"

  @enforce_keys [
    :schema_version,
    :fragment_ref,
    :invocation_ref,
    :tenant_ref,
    :stream_ref,
    :sequence,
    :chunk_ref,
    :chunk_hash,
    :byte_count,
    :trace_ref,
    :redaction_class
  ]
  defstruct [
    :schema_version,
    :fragment_ref,
    :invocation_ref,
    :tenant_ref,
    :stream_ref,
    :sequence,
    :chunk_ref,
    :chunk_hash,
    :byte_count,
    :trace_ref,
    :redaction_class,
    token_count: nil,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          schema_version: String.t(),
          fragment_ref: String.t(),
          invocation_ref: String.t(),
          tenant_ref: String.t(),
          stream_ref: String.t(),
          sequence: non_neg_integer(),
          chunk_ref: String.t(),
          chunk_hash: String.t(),
          byte_count: non_neg_integer(),
          token_count: non_neg_integer() | nil,
          trace_ref: String.t(),
          redaction_class: String.t(),
          metadata: map()
        }

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = fragment), do: normalize(fragment)

  def new(attrs) do
    attrs
    |> Validation.attrs_map()
    |> build()
    |> normalize()
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, fragment} -> fragment
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = fragment) do
    %{
      "schema_version" => fragment.schema_version,
      "fragment_ref" => fragment.fragment_ref,
      "invocation_ref" => fragment.invocation_ref,
      "tenant_ref" => fragment.tenant_ref,
      "stream_ref" => fragment.stream_ref,
      "sequence" => fragment.sequence,
      "chunk_ref" => fragment.chunk_ref,
      "chunk_hash" => fragment.chunk_hash,
      "byte_count" => fragment.byte_count,
      "token_count" => fragment.token_count,
      "trace_ref" => fragment.trace_ref,
      "redaction_class" => fragment.redaction_class,
      "metadata" => fragment.metadata
    }
    |> Contracts.dump_json_safe!()
  end

  @spec canonical_hash(t()) :: String.t()
  def canonical_hash(%__MODULE__{} = fragment), do: fragment |> dump() |> Canonical.checksum!()

  defp build(attrs) do
    base = %__MODULE__{
      schema_version: Contracts.get(attrs, :schema_version, @schema_version),
      fragment_ref: Contracts.get(attrs, :fragment_ref),
      invocation_ref: Validation.required_string!(attrs, :invocation_ref, "invocation_ref"),
      tenant_ref: Validation.required_string!(attrs, :tenant_ref, "tenant_ref"),
      stream_ref: Validation.required_string!(attrs, :stream_ref, "stream_ref"),
      sequence: Contracts.fetch_required!(attrs, :sequence, "sequence"),
      chunk_ref: Validation.required_string!(attrs, :chunk_ref, "chunk_ref"),
      chunk_hash:
        attrs
        |> Validation.required_string!(:chunk_hash, "chunk_hash")
        |> Validation.checksum!("chunk_hash"),
      byte_count: Contracts.fetch_required!(attrs, :byte_count, "byte_count"),
      token_count: Contracts.get(attrs, :token_count),
      trace_ref: Validation.required_string!(attrs, :trace_ref, "trace_ref"),
      redaction_class: Validation.required_string!(attrs, :redaction_class, "redaction_class"),
      metadata: Validation.optional_map!(attrs, :metadata, "metadata", %{})
    }

    %__MODULE__{base | fragment_ref: base.fragment_ref || derived_fragment_ref(base)}
  end

  defp normalize(%__MODULE__{} = fragment) do
    unless fragment.schema_version == @schema_version do
      raise ArgumentError,
            "schema_version must be #{@schema_version}, got: #{inspect(fragment.schema_version)}"
    end

    validate_non_negative_integer!(fragment.sequence, "sequence")
    validate_non_negative_integer!(fragment.byte_count, "byte_count")

    if not is_nil(fragment.token_count) do
      validate_non_negative_integer!(fragment.token_count, "token_count")
    end

    Validation.ensure_no_raw_payloads!(fragment.metadata, "metadata")
    {:ok, fragment}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp derived_fragment_ref(%__MODULE__{} = fragment) do
    value =
      fragment
      |> Map.from_struct()
      |> Map.put(:fragment_ref, nil)

    Canonical.artifact_ref("jido-model-invocation-stream-fragment", value)
  end

  defp validate_non_negative_integer!(value, _field_name) when is_integer(value) and value >= 0,
    do: value

  defp validate_non_negative_integer!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a non-negative integer, got: #{inspect(value)}"
  end
end
