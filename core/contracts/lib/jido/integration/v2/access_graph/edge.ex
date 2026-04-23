defmodule Jido.Integration.V2.AccessGraph.Edge do
  @moduledoc """
  Epoch-stamped access graph edge.

  Contract: `Platform.AccessGraph.Edge.v1`.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef

  @contract_name "Platform.AccessGraph.Edge.v1"
  @contract_version "1.0.0"
  @edge_types [:ua, :ar, :us, :sr, :up, :aur]

  @fields [
    :contract_name,
    :contract_version,
    :edge_id,
    :edge_type,
    :head_ref,
    :tail_ref,
    :tenant_ref,
    :epoch_start,
    :epoch_end,
    :granting_authority_ref,
    :revoking_authority_ref,
    :evidence_refs,
    :policy_refs,
    :metadata
  ]

  @enforce_keys @fields -- [:epoch_end, :revoking_authority_ref]
  defstruct @fields

  @type edge_type :: :ua | :ar | :us | :sr | :up | :aur
  @type t :: %__MODULE__{
          contract_name: String.t(),
          contract_version: String.t(),
          edge_id: String.t(),
          edge_type: edge_type(),
          head_ref: String.t(),
          tail_ref: String.t(),
          tenant_ref: String.t(),
          epoch_start: pos_integer(),
          epoch_end: pos_integer() | nil,
          granting_authority_ref: GovernanceRef.t(),
          revoking_authority_ref: GovernanceRef.t() | nil,
          evidence_refs: [EvidenceRef.t()],
          policy_refs: [String.t()],
          metadata: map()
        }

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec edge_types() :: [edge_type()]
  def edge_types, do: @edge_types

  @spec identity_fields() :: [atom()]
  def identity_fields do
    [
      :edge_id,
      :edge_type,
      :head_ref,
      :tail_ref,
      :tenant_ref,
      :epoch_start,
      :granting_authority_ref
    ]
  end

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = edge), do: normalize(edge)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = edge) do
    case normalize(edge) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec active_at_epoch?(t(), pos_integer()) :: boolean()
  def active_at_epoch?(%__MODULE__{} = edge, epoch) when is_integer(epoch) and epoch > 0 do
    edge.epoch_start <= epoch and (is_nil(edge.epoch_end) or edge.epoch_end > epoch)
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = edge) do
    %{
      contract_name: edge.contract_name,
      contract_version: edge.contract_version,
      edge_id: edge.edge_id,
      edge_type: edge.edge_type,
      head_ref: edge.head_ref,
      tail_ref: edge.tail_ref,
      tenant_ref: edge.tenant_ref,
      epoch_start: edge.epoch_start,
      epoch_end: edge.epoch_end,
      granting_authority_ref: GovernanceRef.dump(edge.granting_authority_ref),
      revoking_authority_ref: maybe_dump_governance(edge.revoking_authority_ref),
      evidence_refs: Enum.map(edge.evidence_refs, &EvidenceRef.dump/1),
      policy_refs: edge.policy_refs,
      metadata: edge.metadata
    }
  end

  defp build!(attrs) do
    attrs = Map.new(attrs)

    edge = %__MODULE__{
      contract_name:
        attrs
        |> Contracts.get(:contract_name, @contract_name)
        |> validate_literal!(@contract_name, :contract_name),
      contract_version:
        attrs
        |> Contracts.get(:contract_version, @contract_version)
        |> validate_literal!(@contract_version, :contract_version),
      edge_id:
        attrs
        |> Contracts.get(:edge_id, Contracts.next_id("access_graph_edge"))
        |> required_string(:edge_id),
      edge_type:
        attrs
        |> Contracts.fetch_required!(:edge_type, field(:edge_type))
        |> Contracts.validate_enum_atomish!(@edge_types, field(:edge_type)),
      head_ref:
        attrs |> Contracts.fetch_required!(:head_ref, field(:head_ref)) |> ref!(:head_ref),
      tail_ref:
        attrs |> Contracts.fetch_required!(:tail_ref, field(:tail_ref)) |> ref!(:tail_ref),
      tenant_ref:
        attrs |> Contracts.fetch_required!(:tenant_ref, field(:tenant_ref)) |> ref!(:tenant_ref),
      epoch_start:
        attrs
        |> Contracts.fetch_required!(:epoch_start, field(:epoch_start))
        |> positive_integer!(:epoch_start),
      epoch_end: optional_positive_integer(attrs, :epoch_end),
      granting_authority_ref:
        attrs
        |> Contracts.get(:granting_authority_ref)
        |> required_governance_ref!(:granting_authority_ref),
      revoking_authority_ref:
        attrs
        |> Contracts.get(:revoking_authority_ref)
        |> optional_governance_ref!(:revoking_authority_ref),
      evidence_refs:
        attrs
        |> Contracts.get(:evidence_refs, [])
        |> evidence_refs!(),
      policy_refs:
        attrs
        |> Contracts.get(:policy_refs, [])
        |> Contracts.normalize_string_list!(field(:policy_refs)),
      metadata:
        attrs
        |> Contracts.get(:metadata, %{})
        |> Contracts.validate_map!(field(:metadata))
    }

    validate_controlled_close!(edge)
  end

  defp normalize(%__MODULE__{} = edge) do
    {:ok, edge |> dump() |> build!()}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_controlled_close!(%__MODULE__{epoch_end: nil} = edge), do: edge

  defp validate_controlled_close!(%__MODULE__{revoking_authority_ref: nil}) do
    raise ArgumentError, "#{field(:revoking_authority_ref)} is required when epoch_end is set"
  end

  defp validate_controlled_close!(%__MODULE__{} = edge) do
    if edge.epoch_end > edge.epoch_start do
      edge
    else
      raise ArgumentError, "#{field(:epoch_end)} must be greater than epoch_start"
    end
  end

  defp required_governance_ref!(nil, key), do: raise(ArgumentError, "#{field(key)} is required")

  defp required_governance_ref!(value, key), do: optional_governance_ref!(value, key)

  defp optional_governance_ref!(nil, _key), do: nil
  defp optional_governance_ref!(%GovernanceRef{} = value, _key), do: value

  defp optional_governance_ref!(value, key) when is_map(value) or is_list(value) do
    value
    |> normalize_ref_attrs()
    |> GovernanceRef.new!()
  rescue
    error in ArgumentError ->
      reraise ArgumentError,
              [message: "#{field(key)} is invalid: #{error.message}"],
              __STACKTRACE__
  end

  defp optional_governance_ref!(value, key) do
    raise ArgumentError, "#{field(key)} must be a GovernanceRef, got: #{inspect(value)}"
  end

  defp evidence_refs!(values) when is_list(values) do
    Enum.map(values, fn
      %EvidenceRef{} = value ->
        value

      value when is_map(value) or is_list(value) ->
        value
        |> normalize_ref_attrs()
        |> EvidenceRef.new!()

      value ->
        raise ArgumentError,
              "#{field(:evidence_refs)} must contain EvidenceRef values, got: #{inspect(value)}"
    end)
  end

  defp evidence_refs!(values) do
    raise ArgumentError, "#{field(:evidence_refs)} must be a list, got: #{inspect(values)}"
  end

  defp normalize_ref_attrs(values) when is_list(values),
    do: values |> Map.new() |> normalize_ref_attrs()

  defp normalize_ref_attrs(values) when is_map(values) do
    values
    |> Map.new(fn {key, value} -> {known_ref_key(key), normalize_ref_value(value)} end)
  end

  defp normalize_ref_value(values) when is_list(values),
    do: Enum.map(values, &normalize_ref_value/1)

  defp normalize_ref_value(values) when is_map(values), do: normalize_ref_attrs(values)
  defp normalize_ref_value(value), do: value

  defp known_ref_key(key) when is_atom(key), do: key

  defp known_ref_key(key) when is_binary(key) do
    case key do
      "ref" -> :ref
      "kind" -> :kind
      "id" -> :id
      "subject" -> :subject
      "evidence" -> :evidence
      "packet_ref" -> :packet_ref
      "metadata" -> :metadata
      other -> other
    end
  end

  defp maybe_dump_governance(nil), do: nil
  defp maybe_dump_governance(%GovernanceRef{} = value), do: GovernanceRef.dump(value)

  defp optional_positive_integer(attrs, key) do
    case Contracts.get(attrs, key) do
      nil -> nil
      value -> positive_integer!(value, key)
    end
  end

  defp positive_integer!(value, key), do: Contracts.validate_positive_integer!(value, field(key))

  defp ref!(value, key), do: required_string(value, key)

  defp required_string(value, key), do: Contracts.validate_non_empty_string!(value, field(key))

  defp validate_literal!(value, expected, _key) when value == expected, do: value

  defp validate_literal!(value, expected, key) do
    raise ArgumentError, "#{field(key)} must be #{expected}, got: #{inspect(value)}"
  end

  defp field(key), do: "access_graph_edge.#{key}"
end
