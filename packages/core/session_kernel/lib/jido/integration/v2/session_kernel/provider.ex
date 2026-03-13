defmodule Jido.Integration.V2.SessionKernel.Provider do
  @moduledoc """
  Behaviour for session-backed capability providers.
  """

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.RuntimeResult

  @callback reuse_key(Capability.t(), map()) :: term()
  @callback open_session(Capability.t(), map()) :: {:ok, map()}
  @callback execute(Capability.t(), map(), map(), map()) ::
              {:ok, map() | RuntimeResult.t(), map()} | {:error, term(), map()}
end
