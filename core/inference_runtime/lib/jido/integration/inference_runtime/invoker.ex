defmodule Jido.Integration.InferenceRuntime.Invoker do
  @moduledoc """
  Backend behaviour for explicit model invocation execution.
  """

  alias Jido.Integration.ModelInvocation.Request

  @callback invoke(Request.t(), keyword()) :: {:ok, map()} | {:error, term()}
end
