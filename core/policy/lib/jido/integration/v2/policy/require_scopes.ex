defmodule Jido.Integration.V2.Policy.RequireScopes do
  @moduledoc false

  @behaviour Jido.Integration.V2.Policy.Rule

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Credential

  @impl true
  def evaluate(%Capability{} = capability, %Credential{} = credential, _input, %{
        contract: contract
      }) do
    required = contract.capability.required_scopes || Capability.required_scopes(capability)
    missing = required -- credential.scopes

    case missing do
      [] -> :ok
      _ -> {:deny, ["missing required scopes: #{Enum.join(missing, ", ")}"]}
    end
  end
end
