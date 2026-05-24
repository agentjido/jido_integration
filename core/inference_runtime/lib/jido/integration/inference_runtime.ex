defmodule Jido.Integration.InferenceRuntime do
  @moduledoc """
  Explicit runtime for governed model invocation requests.
  """

  alias Jido.Integration.InferenceRuntime.RuntimeDeps
  alias Jido.Integration.ModelInvocation.Request

  @spec invoke(Request.t() | map() | keyword(), keyword()) :: {:ok, map()} | {:error, term()}
  def invoke(request_or_attrs, opts \\ []) do
    with {:ok, request} <- Request.new(request_or_attrs),
         {:ok, deps} <- RuntimeDeps.new(opts) do
      deps.invoker.invoke(request, opts)
    end
  end
end
