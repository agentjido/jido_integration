defmodule Jido.Integration.AgentInterop do
  @moduledoc """
  Generic external-agent interop contracts.

  These contracts describe lower agent capabilities as governed data. They do
  not name or implement any concrete external-agent protocol.
  """

  alias Jido.Integration.AgentInterop.Capability
  alias Jido.Integration.AgentInterop.Descriptor
  alias Jido.Integration.AgentInterop.Invocation
  alias Jido.Integration.AgentInterop.PolicyRef
  alias Jido.Integration.AgentInterop.Receipt

  @spec contract_modules() :: [module()]
  def contract_modules do
    [Descriptor, Capability, Invocation, Receipt, PolicyRef]
  end
end
