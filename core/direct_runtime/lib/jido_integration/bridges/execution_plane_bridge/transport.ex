defmodule JidoIntegration.Bridges.ExecutionPlaneBridge.Transport do
  @moduledoc """
  Caller-owned transport contract for Jido Integration lower-lane execution.
  """

  @type result :: {:ok, map()} | {:error, map()}

  @callback execute_lane(request :: map(), opts :: keyword()) :: result()
end
