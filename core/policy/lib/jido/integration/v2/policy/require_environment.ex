defmodule Jido.Integration.V2.Policy.RequireEnvironment do
  @moduledoc false

  @behaviour Jido.Integration.V2.Policy.Rule

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Credential

  @impl true
  def evaluate(%Capability{} = capability, %Credential{}, _input, %{
        gateway: gateway,
        contract: contract
      }) do
    case contract.environment.allowed do
      [] ->
        :ok

      allowed ->
        if environment_allowed?(gateway.environment, allowed) do
          :ok
        else
          {:deny,
           [
             "environment #{environment_label(gateway.environment)} is not permitted for #{capability.id}"
           ]}
        end
    end
  end

  defp environment_allowed?(nil, _allowed), do: false
  defp environment_allowed?(environment, allowed), do: to_string(environment) in allowed

  defp environment_label(nil), do: "<unset>"
  defp environment_label(environment), do: to_string(environment)
end
