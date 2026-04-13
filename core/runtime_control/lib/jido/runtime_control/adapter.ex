defmodule Jido.RuntimeControl.Adapter do
  @moduledoc "Behaviour that all CLI agent adapters must implement."

  @callback id() :: atom()
  @callback capabilities() :: Jido.RuntimeControl.Capabilities.t()
  @callback run(Jido.RuntimeControl.RunRequest.t(), keyword()) ::
              {:ok, Enumerable.t(Jido.RuntimeControl.Event.t())} | {:error, term()}
  @callback cancel(String.t()) :: :ok | {:error, term()}
  @callback runtime_contract() :: Jido.RuntimeControl.RuntimeContract.t()

  @optional_callbacks [cancel: 1]
end
