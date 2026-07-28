defmodule Jido.Integration.V2.ControlPlane.AttemptObserver do
  @moduledoc """
  Read/stop boundary used to reconcile a previously dispatched provider operation.

  Observers must query the stable external operation reference. They must never
  redispatch the original effect.
  """

  @type terminal ::
          {:completed, map()}
          | {:failed, map()}
          | {:cancelled, map()}

  @callback status(String.t(), map()) ::
              {:ok, :active | terminal() | map()} | {:error, term()}
  @callback cancel(String.t(), map()) :: :ok | {:error, term()}
  @callback cleanup(String.t(), map()) :: :ok | {:error, term()}
end
