defmodule Jido.Integration.V2.Policy.RequireOperation do
  @moduledoc false

  @behaviour Jido.Integration.V2.Policy.Rule

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Credential

  @impl true
  def evaluate(%Capability{} = capability, %Credential{}, _input, %{
        gateway: gateway,
        contract: contract
      }) do
    reasons =
      []
      |> maybe_add(
        capability.id not in gateway.allowed_operations,
        "operation #{capability.id} is not granted for dispatch"
      )
      |> maybe_add(
        capability.id not in contract.capability.allowed_operations,
        "operation #{capability.id} is not permitted by capability policy"
      )

    result(reasons)
  end

  defp maybe_add(reasons, true, reason), do: [reason | reasons]
  defp maybe_add(reasons, false, _reason), do: reasons

  defp result([]), do: :ok
  defp result(reasons), do: {:deny, Enum.reverse(reasons)}
end
