defmodule Jido.ModelProviderRegistry.EndpointIdentityTest do
  use ExUnit.Case, async: true

  alias Jido.ModelProviderRegistry.EndpointProfile

  test "local endpoint identity is separate from remote provider identity" do
    assert {:error, {:identity_conflation_rejected, rejected}} =
             endpoint_attrs()
             |> Map.put(:local_service_identity_ref, "provider-account://tenant-1/openai/acct-a")
             |> EndpointProfile.new()

    assert {:local_service_identity_ref, :provider_account_ref} in rejected

    assert {:ok, endpoint} = EndpointProfile.new(endpoint_attrs())
    assert endpoint.local_service_identity_ref == "local-service://tenant-1/ollama/a"
    assert endpoint.provider_account_ref == "provider-account://tenant-1/openai/acct-a"
  end

  defp endpoint_attrs do
    %{
      tenant_ref: "tenant://tenant-1",
      endpoint_profile_ref: "endpoint-profile://tenant-1/local/ollama/a",
      endpoint_descriptor_ref: "endpoint-descriptor://tenant-1/local/ollama/a",
      provider_ref: "provider://self-hosted-inference",
      provider_account_ref: "provider-account://tenant-1/openai/acct-a",
      local_service_identity_ref: "local-service://tenant-1/ollama/a",
      target_ref: "target://tenant-1/local/ollama/a",
      attach_grant_ref: "attach-grant://tenant-1/local/ollama/a",
      startup_kind: :attach_existing_service,
      management_mode: :externally_managed,
      readiness_ref: "readiness://tenant-1/local/ollama/a",
      health_ref: "health://tenant-1/local/ollama/a",
      endpoint_lease_ref: "endpoint-lease://tenant-1/local/ollama/a"
    }
  end
end
