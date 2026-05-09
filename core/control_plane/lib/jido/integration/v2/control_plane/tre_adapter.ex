defmodule Jido.Integration.V2.ControlPlane.TreAdapter do
  @moduledoc """
  Explicit adapter resolver for the reserved TRE lower lane.

  `:tre_rhai` remains unavailable unless an invocation supplies a concrete
  adapter module through `:tre_adapter`. This keeps the first fake lane from
  changing default connector, session, or fixture dispatch.
  """

  @type opts :: keyword() | map()

  @spec enabled?(opts()) :: boolean()
  def enabled?(opts), do: match?({:ok, _module}, fetch(opts))

  @spec fetch(opts()) :: {:ok, module()} | :error
  def fetch(opts) when is_list(opts) or is_map(opts) do
    case get_opt(opts, :tre_adapter) do
      module when is_atom(module) ->
        if Code.ensure_loaded?(module) and function_exported?(module, :execute, 3) do
          {:ok, module}
        else
          :error
        end

      _other ->
        :error
    end
  end

  defp get_opt(opts, key) when is_list(opts), do: Keyword.get(opts, key)

  defp get_opt(opts, key) when is_map(opts),
    do: Map.get(opts, key) || Map.get(opts, Atom.to_string(key))
end
