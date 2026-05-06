defmodule Jido.Integration.V2.GeneratedOptions do
  @moduledoc false

  @spec keyword!(Macro.t(), Macro.Env.t(), [atom()]) :: keyword()
  def keyword!(opts_ast, caller, allowed_keys) when is_list(allowed_keys) do
    unless Keyword.keyword?(opts_ast) do
      raise ArgumentError, "generated consumer options must be a literal keyword list"
    end

    Enum.map(opts_ast, fn
      {key, value_ast} when is_atom(key) ->
        unless key in allowed_keys do
          raise ArgumentError, "unsupported generated consumer option #{inspect(key)}"
        end

        {key, literal_value!(value_ast, caller)}

      _other ->
        raise ArgumentError, "generated consumer options must use atom keys"
    end)
  end

  defp literal_value!(value, _caller) when is_binary(value) or is_atom(value), do: value

  defp literal_value!({:__aliases__, _metadata, _parts} = ast, caller) do
    case Macro.expand(ast, caller) do
      module when is_atom(module) ->
        module

      other ->
        raise ArgumentError,
              "generated consumer module option must expand to an atom, got: #{inspect(other)}"
    end
  end

  defp literal_value!(value, _caller) do
    raise ArgumentError,
          "generated consumer option must be a literal atom, module alias, or string, got: #{inspect(value)}"
  end
end
