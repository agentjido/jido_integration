defmodule Jido.Integration.V2.StorePostgres.Serialization do
  @moduledoc false

  def dump(%DateTime{} = value), do: DateTime.to_iso8601(value)

  def dump(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> dump()
  end

  def dump(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} ->
      {normalize_key(key), dump(value)}
    end)
  end

  def dump(list) when is_list(list), do: Enum.map(list, &dump/1)
  def dump(value), do: value

  def load(%_{} = struct), do: struct

  def load(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} ->
      {restore_key(key), load(value)}
    end)
  end

  def load(list) when is_list(list), do: Enum.map(list, &load/1)
  def load(value), do: value

  def fetch(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: inspect(key)

  defp restore_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp restore_key(key), do: key
end
