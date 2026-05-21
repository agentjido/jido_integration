defmodule Jido.Integration.AgentRuntimeCapability do
  @moduledoc """
  Compatibility namespace for `AgentRuntimeCapability.v1`.
  """

  alias Jido.Integration.AgentInterop.Capability

  @type t :: Capability.t()

  defdelegate classes(), to: Capability
  defdelegate contract_name(), to: Capability
  defdelegate new(attrs), to: Capability
  defdelegate new!(attrs), to: Capability
  defdelegate to_map(capability), to: Capability
end
