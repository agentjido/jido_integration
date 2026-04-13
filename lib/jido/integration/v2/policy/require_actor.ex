defmodule Jido.Integration.V2.Policy.RequireActor do
  @moduledoc false

  @behaviour Jido.Integration.V2.Policy.Rule

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Credential

  @impl true
  def evaluate(%Capability{} = capability, %Credential{}, _input, %{
        gateway: gateway,
        contract: contract
      }) do
    actor_id = gateway.actor_id

    reasons =
      []
      |> maybe_add(contract.actor.required and blank?(actor_id), "actor_id is required")
      |> maybe_add(
        present?(actor_id) and contract.actor.allowed_ids != [] and
          actor_id not in contract.actor.allowed_ids,
        "actor #{actor_id} is not permitted for #{capability.id}"
      )

    result(reasons)
  end

  defp blank?(nil), do: true
  defp blank?(value), do: String.trim(to_string(value)) == ""
  defp present?(value), do: not blank?(value)

  defp maybe_add(reasons, true, reason), do: [reason | reasons]
  defp maybe_add(reasons, false, _reason), do: reasons

  defp result([]), do: :ok
  defp result(reasons), do: {:deny, Enum.reverse(reasons)}
end
