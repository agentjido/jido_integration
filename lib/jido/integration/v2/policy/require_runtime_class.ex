defmodule Jido.Integration.V2.Policy.RequireRuntimeClass do
  @moduledoc false

  @behaviour Jido.Integration.V2.Policy.Rule

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Credential

  @impl true
  def evaluate(%Capability{} = capability, %Credential{}, _input, %{
        gateway: gateway,
        contract: contract
      }) do
    if gateway.runtime_class in contract.runtime.allowed do
      :ok
    else
      {:deny, ["runtime class #{gateway.runtime_class} is not permitted for #{capability.id}"]}
    end
  end
end
