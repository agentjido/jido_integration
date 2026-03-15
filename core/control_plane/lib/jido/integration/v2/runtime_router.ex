defmodule Jido.Integration.V2.RuntimeRouter do
  @moduledoc """
  Stable runtime-family routing seam for the control plane.
  """

  alias Jido.Integration.V2.{Capability, DirectRuntime, HarnessRuntime, RuntimeResult}

  @spec execute(Capability.t(), map(), map()) ::
          {:ok, RuntimeResult.t()} | {:error, term(), RuntimeResult.t()}
  def execute(%Capability{runtime_class: :direct} = capability, input, context) do
    DirectRuntime.execute(capability, input, context)
  end

  def execute(%Capability{runtime_class: runtime_class} = capability, input, context)
      when runtime_class in [:session, :stream] do
    HarnessRuntime.execute(capability, input, context)
  end

  @spec reset!() :: :ok
  def reset! do
    HarnessRuntime.reset!()
  end
end
