defmodule Jido.Integration.V2.Capability do
  @moduledoc """
  Addressable unit of platform functionality.
  """

  alias Jido.Integration.V2.Contracts

  @enforce_keys [:id, :connector, :runtime_class, :kind, :transport_profile, :handler]
  defstruct [:id, :connector, :runtime_class, :kind, :transport_profile, :handler, metadata: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          connector: String.t(),
          runtime_class: Contracts.runtime_class(),
          kind: atom(),
          transport_profile: atom(),
          handler: module(),
          metadata: map()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    runtime_class = Contracts.validate_runtime_class!(Map.fetch!(attrs, :runtime_class))

    struct!(__MODULE__, %{
      id: Map.fetch!(attrs, :id),
      connector: Map.fetch!(attrs, :connector),
      runtime_class: runtime_class,
      kind: Map.fetch!(attrs, :kind),
      transport_profile: Map.fetch!(attrs, :transport_profile),
      handler: Map.fetch!(attrs, :handler),
      metadata: Map.get(attrs, :metadata, %{})
    })
  end

  @spec required_scopes(t()) :: [String.t()]
  def required_scopes(%__MODULE__{metadata: metadata}) do
    Map.get(metadata, :required_scopes, [])
  end
end
