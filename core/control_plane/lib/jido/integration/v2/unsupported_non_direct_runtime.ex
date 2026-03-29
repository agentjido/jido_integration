defmodule Jido.Integration.V2.UnsupportedNonDirectRuntime do
  @moduledoc false

  alias Jido.Integration.V2.{Capability, RuntimeResult}

  @spec execute(Capability.t(), map(), map()) ::
          {:error, {:unsupported_runtime_class, atom()}, RuntimeResult.t()}
  def execute(%Capability{runtime_class: runtime_class}, _input, _context) do
    runtime_result =
      RuntimeResult.new!(%{
        output: nil,
        events: [
          %{type: "attempt.started"},
          %{
            type: "attempt.failed",
            level: :error,
            payload: %{reason: inspect({:unsupported_runtime_class, runtime_class})}
          }
        ]
      })

    {:error, {:unsupported_runtime_class, runtime_class}, runtime_result}
  end

  @spec reset!() :: :ok
  def reset!, do: :ok
end
