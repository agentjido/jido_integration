defmodule Jido.Integration.V2.Auth.RuntimeContext do
  @moduledoc """
  Explicit runtime dependencies for auth refresh and external secret hydration.
  """

  alias Jido.Integration.V2.Auth.RuntimeConfig
  alias Jido.Integration.V2.Auth.ServiceCore

  @enforce_keys []
  defstruct refresh_handler: nil,
            external_secret_resolver: nil

  @type t :: %__MODULE__{
          refresh_handler: ServiceCore.refresh_handler() | nil,
          external_secret_resolver: ServiceCore.external_secret_resolver() | nil
        }

  @spec current() :: t()
  def current do
    config = RuntimeConfig.current()

    %__MODULE__{
      refresh_handler: Map.get(config, :refresh_handler),
      external_secret_resolver: Map.get(config, :external_secret_resolver)
    }
  end

  @spec from_context(map()) :: t()
  def from_context(%{runtime_context: %__MODULE__{} = runtime_context}), do: runtime_context
  def from_context(_context), do: current()
end
