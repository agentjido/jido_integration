defmodule Jido.Integration.V2.ClockOrdering.HLC do
  @moduledoc """
  Hybrid logical clock for `Platform.ClockOrdering.HLC.V1`.
  """

  alias Jido.Integration.V2.Contracts

  @contract_name "Platform.ClockOrdering.HLC.V1"
  @contract_version "1.0.0"
  @max_remote_skew_ns 60_000_000_000

  @enforce_keys [:wall_ns, :logical, :source_node_ref]
  defstruct [
    :wall_ns,
    :logical,
    :source_node_ref
  ]

  @type t :: %__MODULE__{
          wall_ns: non_neg_integer(),
          logical: non_neg_integer(),
          source_node_ref: String.t()
        }

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = hlc), do: normalize(hlc)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = hlc) do
    case normalize(hlc) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec local_event(t() | nil, String.t(), non_neg_integer()) :: t()
  def local_event(current, source_node_ref, now_ns \\ System.os_time(:nanosecond)) do
    source_node_ref = required_string(source_node_ref, :source_node_ref)
    now_ns = non_negative_integer!(now_ns, :wall_ns)

    case current do
      nil ->
        %__MODULE__{wall_ns: now_ns, logical: 0, source_node_ref: source_node_ref}

      %__MODULE__{} = hlc ->
        if now_ns > hlc.wall_ns do
          %__MODULE__{wall_ns: now_ns, logical: 0, source_node_ref: source_node_ref}
        else
          %__MODULE__{
            wall_ns: hlc.wall_ns,
            logical: hlc.logical + 1,
            source_node_ref: source_node_ref
          }
        end
    end
  end

  @spec merge_remote(t() | nil, t() | map(), String.t(), non_neg_integer()) ::
          {:ok, t()} | {:error, {:clock_skew_rejected, map(), t()}}
  def merge_remote(current, remote, source_node_ref, now_ns \\ System.os_time(:nanosecond)) do
    local = local_event(current, source_node_ref, now_ns)
    remote = new!(remote)
    skew_ns = abs(remote.wall_ns - now_ns)

    if skew_ns > @max_remote_skew_ns do
      metadata = %{
        event: :clock_skew_rejected,
        observed_remote_hlc_skew_ns: skew_ns,
        observed_remote_hlc: dump(remote)
      }

      {:error, {:clock_skew_rejected, metadata, local}}
    else
      {:ok, merge_without_skew!(current, remote, source_node_ref, now_ns)}
    end
  end

  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(%__MODULE__{} = left, %__MODULE__{} = right) do
    cond do
      left.wall_ns < right.wall_ns ->
        :lt

      left.wall_ns > right.wall_ns ->
        :gt

      left.logical < right.logical ->
        :lt

      left.logical > right.logical ->
        :gt

      left.source_node_ref < right.source_node_ref ->
        :lt

      left.source_node_ref > right.source_node_ref ->
        :gt

      true ->
        :eq
    end
  end

  @spec dump(t() | map()) :: map()
  def dump(%__MODULE__{} = hlc) do
    %{"w" => hlc.wall_ns, "l" => hlc.logical, "n" => hlc.source_node_ref}
  end

  def dump(value), do: value |> new!() |> dump()

  @spec canonical_string(t() | map()) :: String.t()
  def canonical_string(value) do
    hlc = new!(value)
    "#{hlc.wall_ns}.#{hlc.logical}.#{URI.encode_www_form(hlc.source_node_ref)}"
  end

  defp merge_without_skew!(current, remote, source_node_ref, now_ns) do
    local = current && new!(current)
    local_wall = if local, do: local.wall_ns, else: 0
    local_logical = if local, do: local.logical, else: 0
    wall_ns = max(max(local_wall, remote.wall_ns), now_ns)

    logical =
      cond do
        wall_ns == local_wall and wall_ns == remote.wall_ns ->
          max(local_logical, remote.logical) + 1

        wall_ns == local_wall ->
          local_logical + 1

        wall_ns == remote.wall_ns ->
          remote.logical + 1

        true ->
          0
      end

    %__MODULE__{
      wall_ns: wall_ns,
      logical: logical,
      source_node_ref: required_string(source_node_ref, :source_node_ref)
    }
  end

  defp build!(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      wall_ns:
        attrs
        |> get(:wall_ns, :w)
        |> non_negative_integer!(:wall_ns),
      logical:
        attrs
        |> get(:logical, :l)
        |> non_negative_integer!(:logical),
      source_node_ref:
        attrs
        |> get(:source_node_ref, :n)
        |> required_string(:source_node_ref)
    }
  end

  defp normalize(%__MODULE__{} = hlc) do
    {:ok, hlc |> dump() |> build!()}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp get(attrs, preferred_key, alternate_key) do
    Contracts.get(attrs, preferred_key) || Contracts.get(attrs, alternate_key)
  end

  defp non_negative_integer!(value, _key) when is_integer(value) and value >= 0, do: value

  defp non_negative_integer!(value, key) do
    raise ArgumentError, "#{field(key)} must be a non-negative integer, got: #{inspect(value)}"
  end

  defp required_string(value, key), do: Contracts.validate_non_empty_string!(value, field(key))

  defp field(key), do: "clock_ordering_hlc.#{key}"
end
