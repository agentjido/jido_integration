defmodule Jido.BoundaryBridge.Contracts do
  @moduledoc false

  @type zoi_schema :: term()

  @spec get(map(), atom(), term()) :: term()
  def get(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  @spec validate_non_empty_string!(term(), String.t()) :: String.t()
  def validate_non_empty_string!(value, field_name) when is_binary(value) do
    if byte_size(String.trim(value)) > 0 do
      value
    else
      raise ArgumentError, "#{field_name} must be a non-empty string, got: #{inspect(value)}"
    end
  end

  def validate_non_empty_string!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a non-empty string, got: #{inspect(value)}"
  end

  @spec normalize_string_list!(term(), String.t()) :: [String.t()]
  def normalize_string_list!(values, field_name) when is_list(values) do
    Enum.map(values, fn value ->
      value
      |> to_string()
      |> validate_non_empty_string!(field_name)
    end)
  end

  def normalize_string_list!(values, field_name) do
    raise ArgumentError, "#{field_name} must be a list, got: #{inspect(values)}"
  end

  @spec any_map_schema() :: zoi_schema()
  def any_map_schema, do: Zoi.map(Zoi.any(), Zoi.any(), [])

  @spec non_empty_string_schema(String.t()) :: zoi_schema()
  def non_empty_string_schema(field_name) when is_binary(field_name) do
    Zoi.string()
    |> Zoi.refine({__MODULE__, :validate_non_empty_string_refine, [field_name]})
  end

  @spec string_list_schema(String.t()) :: zoi_schema()
  def string_list_schema(field_name) when is_binary(field_name) do
    Zoi.any() |> Zoi.refine({__MODULE__, :validate_string_list_refine, [field_name]})
  end

  @spec atomish_schema(String.t()) :: zoi_schema()
  def atomish_schema(field_name) when is_binary(field_name) do
    Zoi.union([Zoi.atom(), Zoi.string()])
    |> Zoi.transform({__MODULE__, :normalize_atomish_transform, [field_name]})
  end

  @spec enumish_schema([atom()], String.t()) :: zoi_schema()
  def enumish_schema(values, field_name) when is_list(values) and is_binary(field_name) do
    Zoi.union([Zoi.enum(values), Zoi.string()])
    |> Zoi.transform({__MODULE__, :normalize_enumish_transform, [values, field_name]})
  end

  @doc false
  @spec validate_non_empty_string_refine(term(), String.t(), keyword()) ::
          :ok | {:error, String.t()}
  def validate_non_empty_string_refine(value, field_name, _opts) do
    validate_non_empty_string!(value, field_name)
    :ok
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc false
  @spec validate_string_list_refine(term(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def validate_string_list_refine(value, field_name, _opts) do
    normalize_string_list!(value, field_name)
    :ok
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc false
  @spec normalize_atomish_transform(term(), String.t(), keyword()) ::
          atom() | {:error, String.t()}
  def normalize_atomish_transform(value, field_name, _opts) do
    normalize_atomish!(value, field_name)
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @doc false
  @spec normalize_enumish_transform(term(), [atom()], String.t(), keyword()) ::
          atom() | {:error, String.t()}
  def normalize_enumish_transform(value, values, field_name, _opts) do
    normalize_enumish!(value, values, field_name)
  rescue
    error in ArgumentError -> {:error, Exception.message(error)}
  end

  @spec normalize_atomish!(term(), String.t()) :: atom()
  def normalize_atomish!(value, _field_name) when is_atom(value), do: value

  def normalize_atomish!(value, field_name) when is_binary(value) do
    value
    |> validate_non_empty_string!(field_name)
    |> String.to_atom()
  end

  def normalize_atomish!(value, field_name) do
    raise ArgumentError, "#{field_name} must be an atom or string, got: #{inspect(value)}"
  end

  @spec normalize_enumish!(term(), [atom()], String.t()) :: atom()
  def normalize_enumish!(value, values, field_name) when is_atom(value) do
    if value in values do
      value
    else
      raise ArgumentError, "invalid #{field_name}: #{inspect(value)}"
    end
  end

  def normalize_enumish!(value, values, field_name) when is_binary(value) do
    case Enum.find(values, &(Atom.to_string(&1) == value)) do
      nil -> raise ArgumentError, "invalid #{field_name}: #{inspect(value)}"
      atom -> atom
    end
  end

  def normalize_enumish!(value, _values, field_name) do
    raise ArgumentError, "#{field_name} must be an atom or string, got: #{inspect(value)}"
  end
end
