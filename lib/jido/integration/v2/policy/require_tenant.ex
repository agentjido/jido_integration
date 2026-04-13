defmodule Jido.Integration.V2.Policy.RequireTenant do
  @moduledoc false

  @behaviour Jido.Integration.V2.Policy.Rule

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Credential

  @impl true
  def evaluate(%Capability{} = capability, %Credential{}, _input, %{
        gateway: gateway,
        contract: contract
      }) do
    tenant_id = gateway.tenant_id
    credential_tenant = credential_tenant(gateway)

    reasons =
      []
      |> maybe_add(contract.tenant.required and blank?(tenant_id), "tenant_id is required")
      |> maybe_add(
        present?(tenant_id) and present?(credential_tenant) and tenant_id != credential_tenant,
        "tenant #{tenant_id} cannot use credential for tenant #{credential_tenant}"
      )
      |> maybe_add(
        present?(tenant_id) and contract.tenant.allowed_ids != [] and
          tenant_id not in contract.tenant.allowed_ids,
        "tenant #{tenant_id} is not permitted for #{capability.id}"
      )

    result(reasons)
  end

  defp credential_tenant(%{credential_ref: nil}), do: nil

  defp credential_tenant(%{credential_ref: credential_ref}) do
    metadata = Map.get(credential_ref, :metadata, %{})
    Contracts.get(metadata, :tenant_id)
  end

  defp blank?(nil), do: true
  defp blank?(value), do: String.trim(to_string(value)) == ""
  defp present?(value), do: not blank?(value)

  defp maybe_add(reasons, true, reason), do: [reason | reasons]
  defp maybe_add(reasons, false, _reason), do: reasons

  defp result([]), do: :ok
  defp result(reasons), do: {:deny, Enum.reverse(reasons)}
end
