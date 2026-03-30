defmodule Jido.BoundaryBridge.Extensions do
  @moduledoc """
  Typed accessors for known boundary-descriptor extension namespaces.
  """

  alias Jido.BoundaryBridge.Extensions.Tracing

  @known_namespaces %{
    "jido.boundary_bridge.tracing" => Tracing
  }

  @spec validate!(map() | keyword() | nil) :: map()
  def validate!(nil), do: %{}

  def validate!(extensions) when is_map(extensions) or is_list(extensions) do
    extensions
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Enum.reduce(%{}, fn {namespace, value}, acc ->
      normalized =
        case Map.fetch(@known_namespaces, namespace) do
          {:ok, parser} -> parser.new!(value)
          :error -> value
        end

      Map.put(acc, namespace, normalized)
    end)
  end

  def validate!(extensions) do
    raise ArgumentError, "extensions must be a map or keyword list, got: #{inspect(extensions)}"
  end

  @spec tracing(map()) :: Tracing.t() | nil
  def tracing(extensions) when is_map(extensions) do
    case Map.get(extensions, "jido.boundary_bridge.tracing") do
      nil -> nil
      %Tracing{} = tracing -> tracing
      value -> Tracing.new!(value)
    end
  end
end
