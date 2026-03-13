defmodule Jido.Integration.V2.Manifest do
  @moduledoc """
  Connector-level declaration of capabilities.
  """

  alias Jido.Integration.V2.Capability

  @enforce_keys [:connector, :capabilities]
  defstruct [:connector, :capabilities, metadata: %{}]

  @type t :: %__MODULE__{
          connector: String.t(),
          capabilities: [Capability.t()],
          metadata: map()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)

    struct!(__MODULE__, %{
      connector: Map.fetch!(attrs, :connector),
      capabilities: Map.fetch!(attrs, :capabilities),
      metadata: Map.get(attrs, :metadata, %{})
    })
  end
end
