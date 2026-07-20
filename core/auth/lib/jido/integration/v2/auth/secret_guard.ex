defmodule Jido.Integration.V2.Auth.SecretGuard do
  @moduledoc """
  Fail-closed validation for values that may cross a durable or telemetry boundary.

  Opaque identity fields ending in `_ref` or `_id` are safe. Raw credential
  material and transient materialization structs are not.
  """

  @sensitive_fragments ~w(
    accesskey accesstoken apikey authorization bearer clientsecret cookie
    password privatekey refreshtoken secret sessiontoken signingkey token
  )

  @transient_modules [
    Jido.Integration.V2.SecretMaterial,
    Jido.Integration.Secrets.SecretHandle
  ]

  @spec validate_durable(term()) :: :ok | {:error, {:secret_material_forbidden, [term()]}}
  def validate_durable(value), do: walk(value, [])

  @spec validate_durable!(term()) :: :ok
  def validate_durable!(value) do
    case validate_durable(value) do
      :ok ->
        :ok

      {:error, reason} ->
        raise ArgumentError, "secret material is not durable: #{inspect(reason)}"
    end
  end

  @spec contains_material?(term(), map()) :: boolean()
  def contains_material?(value, material) when is_map(material) do
    material
    |> flatten_values()
    |> Enum.reject(&is_nil/1)
    |> Enum.any?(&contains_value?(value, &1))
  end

  defp walk(%module{}, path) when module in @transient_modules,
    do: {:error, {:secret_material_forbidden, Enum.reverse(path)}}

  defp walk(%_{} = struct, path), do: walk(Map.from_struct(struct), path)

  defp walk(map, path) when is_map(map) do
    Enum.reduce_while(map, :ok, fn {key, value}, :ok ->
      if sensitive_key?(key) do
        {:halt, {:error, {:secret_material_forbidden, Enum.reverse([key | path])}}}
      else
        case walk(value, [key | path]) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end
    end)
  end

  defp walk(list, path) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case walk(value, [index | path]) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp walk(tuple, path) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> walk(path)
  defp walk(_value, _path), do: :ok

  defp sensitive_key?(key) when is_atom(key), do: sensitive_key?(Atom.to_string(key))

  defp sensitive_key?(key) when is_binary(key) do
    normalized = normalize_key(key)

    not safe_reference_key?(key) and
      Enum.any?(@sensitive_fragments, &String.contains?(normalized, &1))
  end

  defp sensitive_key?(_key), do: false

  defp safe_reference_key?(key) do
    canonical = canonical_key(key)

    String.ends_with?(canonical, ["_ref", "_refs", "_id", "_ids"]) or
      canonical in [
        "credential_handle",
        "cached_tokens",
        "cache_creation_input_tokens",
        "cache_creation_tokens",
        "cache_read_input_tokens",
        "fence_token",
        "lease_fields",
        "max_tokens",
        "requested_tokens",
        "input_tokens",
        "output_tokens",
        "prompt_tokens",
        "reasoning_tokens",
        "completion_tokens",
        "total_tokens",
        "secret_material_redacted"
      ]
  end

  defp normalize_key(key) do
    key
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/u, "")
  end

  defp canonical_key(key) do
    key
    |> String.replace(~r/([a-z0-9])([A-Z])/u, "\\1_\\2")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end

  defp flatten_values(%_{} = struct), do: struct |> Map.from_struct() |> flatten_values()
  defp flatten_values(map) when is_map(map), do: Enum.flat_map(Map.values(map), &flatten_values/1)
  defp flatten_values(list) when is_list(list), do: Enum.flat_map(list, &flatten_values/1)

  defp flatten_values(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> flatten_values()

  defp flatten_values(value), do: [value]

  defp contains_value?(value, secret) when is_binary(value) and is_binary(secret),
    do: secret != "" and String.contains?(value, secret)

  defp contains_value?(%_{} = struct, secret),
    do: struct |> Map.from_struct() |> contains_value?(secret)

  defp contains_value?(map, secret) when is_map(map) do
    Enum.any?(map, fn {key, value} ->
      contains_value?(to_string(key), secret) or contains_value?(value, secret)
    end)
  end

  defp contains_value?(list, secret) when is_list(list),
    do: Enum.any?(list, &contains_value?(&1, secret))

  defp contains_value?(tuple, secret) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> contains_value?(secret)

  defp contains_value?(value, secret), do: value == secret
end
