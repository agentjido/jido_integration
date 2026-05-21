defmodule Jido.Integration.AgentInterop.Validator do
  @moduledoc false

  @raw_secret_keys [
    "api_key",
    "access_token",
    "refresh_token",
    "secret",
    "token",
    "password",
    "private_key",
    "auth_header",
    "authorization",
    "cookie",
    "session_cookie",
    "raw_credential",
    "credential_payload",
    "credential_material",
    "raw_secret",
    "raw_token"
  ]
  @raw_endpoint_keys [
    "url",
    "uri",
    "endpoint",
    "endpoint_url",
    "base_url",
    "raw_endpoint",
    "raw_endpoint_url"
  ]

  @spec attrs!(map() | keyword() | struct(), [atom()], module()) :: map()
  def attrs!(%module{} = attrs, _fields, module), do: Map.from_struct(attrs)

  def attrs!(attrs, fields, module) when is_map(attrs) do
    normalized =
      Map.new(attrs, fn {key, value} ->
        {normalize_key(key, fields, module), value}
      end)

    unknown =
      normalized
      |> Map.keys()
      |> Enum.reject(&(&1 in fields))
      |> Enum.sort()

    if unknown == [] do
      normalized
    else
      raise ArgumentError, "#{inspect(module)} contains unknown fields: #{inspect(unknown)}"
    end
  end

  def attrs!(attrs, fields, module) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      attrs!(Map.new(attrs), fields, module)
    else
      raise ArgumentError, "#{inspect(module)} attrs must be a map, struct, or keyword list"
    end
  end

  def attrs!(_attrs, _fields, module) do
    raise ArgumentError, "#{inspect(module)} attrs must be a map, struct, or keyword list"
  end

  @spec required_string!(term(), atom()) :: String.t()
  def required_string!(value, field) do
    value
    |> optional_string!(field)
    |> case do
      nil -> raise ArgumentError, "#{field} is required"
      value -> value
    end
  end

  @spec optional_string!(term(), atom()) :: String.t() | nil
  def optional_string!(nil, _field), do: nil

  def optional_string!(value, field) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      raise ArgumentError, "#{field} must be a non-empty string"
    else
      trimmed
    end
  end

  def optional_string!(value, field) do
    raise ArgumentError, "#{field} must be a string, got: #{inspect(value)}"
  end

  @spec enum!(term(), [atom()], atom()) :: atom()
  def enum!(value, allowed, field) when is_atom(value) do
    if value in allowed do
      value
    else
      raise ArgumentError, "#{field} must be one of #{inspect(allowed)}, got: #{inspect(value)}"
    end
  end

  def enum!(value, allowed, field) when is_binary(value) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil ->
        raise ArgumentError, "#{field} must be one of #{inspect(allowed)}, got: #{inspect(value)}"

      atom ->
        atom
    end
  end

  def enum!(value, allowed, field) do
    raise ArgumentError, "#{field} must be one of #{inspect(allowed)}, got: #{inspect(value)}"
  end

  @spec optional_enum!(term(), [atom()], atom()) :: atom() | nil
  def optional_enum!(nil, _allowed, _field), do: nil
  def optional_enum!(value, allowed, field), do: enum!(value, allowed, field)

  @spec boolean!(term(), atom()) :: boolean()
  def boolean!(value, _field) when is_boolean(value), do: value

  def boolean!(value, field) do
    raise ArgumentError, "#{field} must be a boolean, got: #{inspect(value)}"
  end

  @spec string_list!(term(), atom()) :: [String.t()]
  def string_list!(values, field) when is_list(values) do
    Enum.map(values, &required_string!(&1, field))
  end

  def string_list!(values, field) do
    raise ArgumentError, "#{field} must be a list of strings, got: #{inspect(values)}"
  end

  @spec non_empty_string_list!(term(), atom()) :: [String.t(), ...]
  def non_empty_string_list!(values, field) do
    values = string_list!(values, field)

    if values == [] do
      raise ArgumentError, "#{field} must not be empty"
    else
      values
    end
  end

  @spec map!(term(), atom()) :: map()
  def map!(value, _field) when is_map(value), do: Map.new(value)

  def map!(value, field) do
    raise ArgumentError, "#{field} must be a map, got: #{inspect(value)}"
  end

  @spec optional_datetime!(term(), atom()) :: DateTime.t() | nil
  def optional_datetime!(nil, _field), do: nil
  def optional_datetime!(%DateTime{} = value, _field), do: DateTime.truncate(value, :microsecond)

  def optional_datetime!(value, field) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :microsecond)
      {:error, reason} -> raise ArgumentError, "#{field} must be ISO8601, got: #{inspect(reason)}"
    end
  end

  def optional_datetime!(value, field) do
    raise ArgumentError, "#{field} must be a DateTime or ISO8601 string, got: #{inspect(value)}"
  end

  @spec reject_raw_secret_material!(term(), atom()) :: :ok
  def reject_raw_secret_material!(value, field) do
    case raw_key_path(value, [], @raw_secret_keys) do
      nil ->
        :ok

      path ->
        raise ArgumentError,
              "#{field} must not contain raw credential material at #{Enum.join(path, ".")}"
    end
  end

  @spec reject_raw_endpoint_material!(term(), atom()) :: :ok
  def reject_raw_endpoint_material!(value, field) do
    case raw_key_path(value, [], @raw_endpoint_keys) do
      nil ->
        :ok

      path ->
        raise ArgumentError,
              "#{field} must not contain raw endpoint material at #{Enum.join(path, ".")}"
    end
  end

  @spec compact_dump(map()) :: map()
  def compact_dump(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), serialize(value)} end)
  end

  defp normalize_key(key, _fields, _module) when is_atom(key), do: key

  defp normalize_key(key, fields, module) when is_binary(key) do
    case Enum.find(fields, &(Atom.to_string(&1) == key)) do
      nil -> key
      field -> field
    end
    |> case do
      field when is_atom(field) ->
        field

      unknown ->
        raise ArgumentError, "#{inspect(module)} contains unknown field: #{inspect(unknown)}"
    end
  end

  defp normalize_key(key, _fields, module) do
    raise ArgumentError, "#{inspect(module)} contains unsupported field key: #{inspect(key)}"
  end

  defp raw_key_path(%_{} = struct, path, key_set) do
    struct
    |> Map.from_struct()
    |> raw_key_path(path, key_set)
  end

  defp raw_key_path(%{} = map, path, key_set) do
    Enum.find_value(map, fn {key, value} ->
      segment = to_string(key)
      next_path = path ++ [segment]

      cond do
        String.downcase(segment) in key_set -> next_path
        is_map(value) or is_list(value) -> raw_key_path(value, next_path, key_set)
        true -> nil
      end
    end)
  end

  defp raw_key_path(values, path, key_set) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.find_value(fn {value, index} ->
      if is_map(value) or is_list(value) do
        raw_key_path(value, path ++ [Integer.to_string(index)], key_set)
      end
    end)
  end

  defp raw_key_path(_value, _path, _key_set), do: nil

  defp serialize(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp serialize(%_{} = value) do
    value
    |> Map.from_struct()
    |> serialize()
  end

  defp serialize(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} -> {to_string(key), serialize(nested_value)} end)
  end

  defp serialize(value) when is_list(value), do: Enum.map(value, &serialize/1)

  defp serialize(value) when is_atom(value),
    do: if(is_nil(value), do: nil, else: Atom.to_string(value))

  defp serialize(value), do: value
end
