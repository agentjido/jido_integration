defmodule Jido.Integration.V2.ClusterInvalidation do
  @moduledoc """
  Cluster invalidation message contract for memory-path cache fanout.
  """

  alias Jido.Integration.V2.{ClockOrdering.HLC, Contracts}

  @contract_name "Platform.ClusterInvalidation.V1"
  @contract_version "1.0.0"
  @topic_segment_regex ~r/\A[a-z0-9_-]+\z/
  @topic_regex ~r/\A[a-z0-9_-]+(\.[a-z0-9_-]+)*\z/
  @global_tenant_ref "tenant://global"
  @global_installation_ref "installation://global"

  @enforce_keys [
    :contract_name,
    :contract_version,
    :invalidation_id,
    :tenant_ref,
    :topic,
    :source_node_ref,
    :commit_lsn,
    :commit_hlc,
    :published_at
  ]
  defstruct [
    :contract_name,
    :contract_version,
    :invalidation_id,
    :tenant_ref,
    :topic,
    :source_node_ref,
    :commit_lsn,
    :commit_hlc,
    :published_at,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          contract_name: String.t(),
          contract_version: String.t(),
          invalidation_id: String.t(),
          tenant_ref: String.t(),
          topic: String.t(),
          source_node_ref: String.t(),
          commit_lsn: String.t(),
          commit_hlc: map(),
          published_at: DateTime.t(),
          metadata: map()
        }

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = message), do: new(Map.from_struct(message))

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    {:ok, new!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = message), do: new!(Map.from_struct(message))

  def new!(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      contract_name:
        attrs
        |> Contracts.get(:contract_name, @contract_name)
        |> validate_literal!(@contract_name, :contract_name),
      contract_version:
        attrs
        |> Contracts.get(:contract_version, @contract_version)
        |> validate_literal!(@contract_version, :contract_version),
      invalidation_id:
        attrs
        |> Contracts.get(:invalidation_id)
        |> required_string(:invalidation_id),
      tenant_ref:
        attrs
        |> Contracts.get(:tenant_ref)
        |> required_string(:tenant_ref),
      topic:
        attrs
        |> Contracts.get(:topic)
        |> topic!(:topic),
      source_node_ref:
        attrs
        |> Contracts.get(:source_node_ref)
        |> required_string(:source_node_ref),
      commit_lsn:
        attrs
        |> Contracts.get(:commit_lsn)
        |> required_string(:commit_lsn),
      commit_hlc:
        attrs
        |> Contracts.get(:commit_hlc)
        |> HLC.dump(),
      published_at:
        attrs
        |> Contracts.get(:published_at)
        |> datetime!(:published_at),
      metadata:
        attrs
        |> Contracts.get(:metadata, %{})
        |> metadata!()
    }
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = message) do
    %{
      contract_name: message.contract_name,
      contract_version: message.contract_version,
      invalidation_id: message.invalidation_id,
      tenant_ref: message.tenant_ref,
      topic: message.topic,
      source_node_ref: message.source_node_ref,
      commit_lsn: message.commit_lsn,
      commit_hlc: message.commit_hlc,
      published_at: DateTime.to_iso8601(message.published_at),
      metadata: Contracts.dump_json_safe!(message.metadata)
    }
  end

  @spec hash_segment(String.t()) :: String.t()
  def hash_segment(ref) do
    ref
    |> required_string(:ref)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  @spec policy_topic!(keyword()) :: String.t()
  def policy_topic!(opts) when is_list(opts) do
    tenant_ref = Keyword.get(opts, :tenant_ref) || @global_tenant_ref
    installation_ref = Keyword.get(opts, :installation_ref) || @global_installation_ref
    kind = opts |> Keyword.fetch!(:kind) |> kind_segment!()
    policy_id = Keyword.fetch!(opts, :policy_id)
    version = opts |> Keyword.fetch!(:version) |> positive_integer!(:version)

    topic!([
      "memory",
      "policy",
      hash_segment(tenant_ref),
      hash_segment(installation_ref),
      kind,
      hash_segment(policy_id),
      Integer.to_string(version)
    ])
  end

  @spec graph_topic!(String.t(), pos_integer()) :: String.t()
  def graph_topic!(tenant_ref, epoch) do
    topic!(["memory", "graph", hash_segment(tenant_ref), "epoch", positive_epoch!(epoch)])
  end

  @spec fragment_topic!(String.t(), String.t()) :: String.t()
  def fragment_topic!(tenant_ref, fragment_id) do
    topic!(["memory", "fragment", hash_segment(tenant_ref), hash_segment(fragment_id)])
  end

  @spec invalidation_topic!(String.t(), String.t()) :: String.t()
  def invalidation_topic!(tenant_ref, invalidation_id) do
    topic!(["memory", "invalidation", hash_segment(tenant_ref), hash_segment(invalidation_id)])
  end

  defp topic!(segments) when is_list(segments) do
    segments
    |> Enum.map_join(".", &segment!/1)
    |> topic!(:topic)
  end

  defp topic!(topic, key) when is_binary(topic) do
    if Regex.match?(@topic_regex, topic) do
      topic
    else
      raise ArgumentError, "#{field(key)} must use lowercase ASCII topic segments"
    end
  end

  defp topic!(topic, key) do
    raise ArgumentError, "#{field(key)} must be a topic string, got: #{inspect(topic)}"
  end

  defp segment!(segment) do
    segment = required_string(segment, :topic_segment)

    if Regex.match?(@topic_segment_regex, segment) do
      segment
    else
      raise ArgumentError, "#{field(:topic_segment)} is invalid: #{inspect(segment)}"
    end
  end

  defp kind_segment!(kind) when is_atom(kind), do: kind |> Atom.to_string() |> kind_segment!()

  defp kind_segment!(kind) when is_binary(kind) do
    kind
    |> String.downcase()
    |> segment!()
  end

  defp kind_segment!(kind) do
    raise ArgumentError, "#{field(:kind)} is invalid: #{inspect(kind)}"
  end

  defp positive_epoch!(epoch) when is_integer(epoch) and epoch > 0, do: Integer.to_string(epoch)

  defp positive_epoch!(epoch) do
    raise ArgumentError, "#{field(:epoch)} must be a positive integer, got: #{inspect(epoch)}"
  end

  defp positive_integer!(value, _key) when is_integer(value) and value > 0, do: value

  defp positive_integer!(value, key) do
    raise ArgumentError, "#{field(key)} must be a positive integer, got: #{inspect(value)}"
  end

  defp datetime!(%DateTime{} = value, _key), do: value

  defp datetime!(value, key) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> raise ArgumentError, "#{field(key)} must be a DateTime"
    end
  end

  defp datetime!(value, key) do
    raise ArgumentError, "#{field(key)} must be a DateTime, got: #{inspect(value)}"
  end

  defp metadata!(nil), do: %{}
  defp metadata!(value) when is_map(value), do: value

  defp metadata!(value) do
    raise ArgumentError, "#{field(:metadata)} must be a map, got: #{inspect(value)}"
  end

  defp validate_literal!(value, expected, _key) when value == expected, do: value

  defp validate_literal!(value, expected, key) do
    raise ArgumentError, "#{field(key)} must be #{expected}, got: #{inspect(value)}"
  end

  defp required_string(value, key), do: Contracts.validate_non_empty_string!(value, field(key))
  defp field(key), do: "cluster_invalidation.#{key}"
end
