defmodule Jido.Integration.InferenceRuntime.RuntimeDeps do
  @moduledoc """
  Explicit dependency bundle for model invocation runtime.
  """

  alias Jido.Integration.InferenceRuntime.FakeInvoker

  @enforce_keys [:invoker]
  defstruct [:invoker]

  @type t :: %__MODULE__{invoker: module()}

  @spec new(keyword() | map() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = deps), do: validate(deps)

  def new(opts) when is_list(opts) do
    opts
    |> Map.new()
    |> new()
  end

  def new(opts) when is_map(opts) do
    validate(%__MODULE__{invoker: Map.get(opts, :invoker, FakeInvoker)})
  end

  def new(opts) do
    {:error,
     ArgumentError.exception("runtime deps must be a keyword list or map, got: #{inspect(opts)}")}
  end

  defp validate(%__MODULE__{} = deps) do
    if function_exported?(deps.invoker, :invoke, 2) do
      {:ok, deps}
    else
      {:error, ArgumentError.exception("invoker must export invoke/2")}
    end
  end
end
