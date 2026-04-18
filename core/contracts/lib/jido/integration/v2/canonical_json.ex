defmodule Jido.Integration.V2.CanonicalJson do
  @moduledoc """
  lower-gateway-owned canonical JSON normalization and RFC 8785 / JCS encoding helpers.
  """

  alias Jido.Integration.V2.Contracts

  @typedoc "JSON-safe scalar value after normalization"
  @type scalar :: nil | boolean() | integer() | float() | String.t()

  @typedoc "Normalized JSON value with string-keyed objects only"
  @type value :: scalar() | [value()] | %{required(String.t()) => value()}

  @spec normalize(term()) :: {:ok, value()} | {:error, Exception.t()}
  def normalize(input) do
    {:ok, normalize!(input)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec normalize!(term()) :: value()
  def normalize!(input), do: normalize_value!(input, [])

  @spec encode(term()) :: {:ok, String.t()} | {:error, Exception.t()}
  def encode(input) do
    {:ok, encode!(input)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec encode!(term()) :: String.t()
  def encode!(input) do
    input
    |> normalize!()
    |> Jcs.encode()
  end

  @spec checksum!(term()) :: Contracts.checksum()
  def checksum!(input) do
    digest =
      input
      |> encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "sha256:#{digest}"
  end

  defp normalize_value!(value, _path)
       when is_binary(value) or is_integer(value) or is_boolean(value) or is_nil(value),
       do: value

  defp normalize_value!([], _path), do: []

  defp normalize_value!(value, path) when is_float(value) do
    if finite_float?(value) do
      value
    else
      raise ArgumentError, "#{format_path(path)} must be a finite float, got: #{inspect(value)}"
    end
  end

  defp normalize_value!(value, _path) when is_atom(value), do: Atom.to_string(value)

  defp normalize_value!(value, path) when is_list(value) do
    if Keyword.keyword?(value) do
      normalize_object_entries!(value, path, :keyword_list)
    else
      value
      |> Enum.with_index()
      |> Enum.map(fn {entry, index} -> normalize_value!(entry, [index | path]) end)
    end
  end

  defp normalize_value!(%_{} = value, path) do
    raise ArgumentError,
          "#{format_path(path)} contains unsupported struct #{inspect(value.__struct__)}; " <>
            "dump packet-owned structs before canonicalization"
  end

  defp normalize_value!(value, path) when is_map(value) do
    normalize_object_entries!(Map.to_list(value), path, :map)
  end

  defp normalize_value!(value, path) do
    raise ArgumentError,
          "#{format_path(path)} contains unsupported non-JSON value: #{inspect(value)}"
  end

  defp normalize_object_entries!(entries, path, source_kind) do
    Enum.reduce(entries, %{}, fn {key, nested_value}, acc ->
      normalized_key = normalize_object_key!(key, path)

      if Map.has_key?(acc, normalized_key) do
        raise ArgumentError,
              "#{format_path(path)} contains duplicate #{source_kind} key after normalization: " <>
                inspect(normalized_key)
      end

      Map.put(acc, normalized_key, normalize_value!(nested_value, [normalized_key | path]))
    end)
  end

  defp normalize_object_key!(key, _path) when is_binary(key), do: key
  defp normalize_object_key!(key, _path) when is_atom(key), do: Atom.to_string(key)

  defp normalize_object_key!(key, path) do
    raise ArgumentError,
          "#{format_path(path)} contains unsupported object key #{inspect(key)}; " <>
            "canonical JSON object keys must be strings or atoms"
  end

  defp finite_float?(value) when is_float(value) do
    value
    |> :erlang.float_to_binary([:short])
    |> then(&(&1 not in ["nan", "inf", "-inf"]))
  end

  defp format_path([]), do: "value"

  defp format_path(path) do
    path
    |> Enum.reverse()
    |> Enum.reduce("value", fn
      segment, acc when is_integer(segment) -> "#{acc}[#{segment}]"
      segment, acc -> "#{acc}.#{segment}"
    end)
  end
end
