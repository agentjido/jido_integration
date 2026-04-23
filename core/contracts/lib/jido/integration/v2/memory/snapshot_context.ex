defmodule Jido.Integration.V2.Memory.SnapshotContext do
  @moduledoc """
  Epoch pinning context for `Platform.Memory.SnapshotContext.V1`.
  """

  alias Jido.Integration.V2.ClockOrdering.HLC
  alias Jido.Integration.V2.Contracts

  @contract_name "Platform.Memory.SnapshotContext.V1"
  @contract_version "1.0.0"

  @fields [
    :contract_name,
    :contract_version,
    :tenant_ref,
    :snapshot_epoch,
    :pinned_at,
    :source_node_ref,
    :commit_lsn,
    :commit_hlc,
    :latency_us
  ]

  @enforce_keys @fields -- [:source_node_ref, :commit_lsn, :commit_hlc, :latency_us]
  defstruct @fields

  @type t :: %__MODULE__{
          contract_name: String.t(),
          contract_version: String.t(),
          tenant_ref: String.t(),
          snapshot_epoch: non_neg_integer(),
          pinned_at: DateTime.t(),
          source_node_ref: String.t() | nil,
          commit_lsn: String.t() | nil,
          commit_hlc: HLC.t() | nil,
          latency_us: non_neg_integer() | nil
        }

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = context), do: normalize(context)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = context) do
    case normalize(context) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = context) do
    %{
      contract_name: context.contract_name,
      contract_version: context.contract_version,
      tenant_ref: context.tenant_ref,
      snapshot_epoch: context.snapshot_epoch,
      pinned_at: DateTime.to_iso8601(context.pinned_at),
      source_node_ref: context.source_node_ref,
      commit_lsn: context.commit_lsn,
      commit_hlc: maybe_dump_hlc(context.commit_hlc),
      latency_us: context.latency_us
    }
  end

  defp build!(attrs) do
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
      tenant_ref:
        attrs
        |> Contracts.get(:tenant_ref)
        |> required_string(:tenant_ref),
      snapshot_epoch:
        attrs
        |> Contracts.get(:snapshot_epoch)
        |> non_negative_integer!(:snapshot_epoch),
      pinned_at:
        attrs
        |> Contracts.get(:pinned_at)
        |> datetime!(:pinned_at),
      source_node_ref: optional_string(attrs, :source_node_ref),
      commit_lsn: optional_string(attrs, :commit_lsn),
      commit_hlc: optional_hlc(attrs),
      latency_us: optional_non_negative_integer(attrs, :latency_us)
    }
  end

  defp normalize(%__MODULE__{} = context) do
    {:ok, context |> dump() |> build!()}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp optional_hlc(attrs) do
    case Contracts.get(attrs, :commit_hlc) do
      nil -> nil
      value -> HLC.new!(value)
    end
  end

  defp maybe_dump_hlc(nil), do: nil
  defp maybe_dump_hlc(%HLC{} = hlc), do: HLC.dump(hlc)

  defp optional_string(attrs, key) do
    case Contracts.get(attrs, key) do
      nil -> nil
      value -> required_string(value, key)
    end
  end

  defp optional_non_negative_integer(attrs, key) do
    case Contracts.get(attrs, key) do
      nil -> nil
      value -> non_negative_integer!(value, key)
    end
  end

  defp non_negative_integer!(value, _key) when is_integer(value) and value >= 0, do: value

  defp non_negative_integer!(value, key) do
    raise ArgumentError, "#{field(key)} must be a non-negative integer, got: #{inspect(value)}"
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

  defp required_string(value, key), do: Contracts.validate_non_empty_string!(value, field(key))

  defp validate_literal!(value, expected, key) do
    if value == expected do
      value
    else
      raise ArgumentError, "#{field(key)} must be #{inspect(expected)}, got: #{inspect(value)}"
    end
  end

  defp field(key), do: "memory_snapshot_context.#{key}"
end
