defmodule Jido.Integration.V2.StreamRuntime.Provider do
  @moduledoc """
  Behaviour for pull-oriented stream providers.
  """

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.RuntimeResult

  @callback reuse_key(Capability.t(), map(), map()) :: term()
  @callback open_stream(Capability.t(), map(), map()) :: {:ok, map()}
  @callback pull(Capability.t(), map(), map(), map()) ::
              {:ok, map() | RuntimeResult.t(), map()} | {:error, term(), map()}
end
