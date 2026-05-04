defmodule Jido.Integration.V2.ConnectorRegistryTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.ConnectorRegistry

  test "registers one provider with multiple account identities without merging them" do
    assert {:ok, account_a} = ConnectorRegistry.register(valid_attrs())

    assert {:ok, account_b} =
             valid_attrs()
             |> Map.put(:provider_account_ref, "provider-account://tenant-1/github/account-b")
             |> Map.put(:connector_instance_ref, "connector-instance://tenant-1/github/rest-b")
             |> Map.put(
               :credential_handle_ref,
               "credential-handle://tenant-1/github/account-b/pat"
             )
             |> ConnectorRegistry.register()

    assert account_a.provider_ref == account_b.provider_ref
    refute ConnectorRegistry.identity_key(account_a) == ConnectorRegistry.identity_key(account_b)
  end

  test "provider name alone cannot select credentials" do
    assert {:ok, entry} = ConnectorRegistry.register(valid_attrs())

    assert {:error, {:missing_selection_refs, missing}} =
             ConnectorRegistry.select_credential([entry], provider_ref: "provider://github")

    assert :provider_account_ref in missing
    assert :connector_instance_ref in missing
    assert :credential_handle_ref in missing
    assert :tenant_ref in missing
    assert :policy_revision_ref in missing
  end

  test "connector instance alone cannot select credentials" do
    assert {:ok, entry} = ConnectorRegistry.register(valid_attrs())

    assert {:error, {:missing_selection_refs, missing}} =
             ConnectorRegistry.select_credential([entry],
               provider_ref: "provider://github",
               connector_instance_ref: "connector-instance://tenant-1/github/rest-a"
             )

    assert :provider_account_ref in missing
    assert :credential_handle_ref in missing
  end

  test "credential selection is tenant scoped and policy revision scoped" do
    assert {:ok, entry} = ConnectorRegistry.register(valid_attrs())

    assert {:ok, selected} = ConnectorRegistry.select_credential([entry], selection_attrs())
    assert selected.provider_account_ref == "provider-account://tenant-1/github/account-a"

    assert {:error, :credential_selection_not_found} =
             ConnectorRegistry.select_credential(
               [entry],
               Map.put(
                 selection_attrs(),
                 :policy_revision_ref,
                 "policy-revision://tenant-1/auth/2"
               )
             )

    assert {:error, :credential_selection_not_found} =
             ConnectorRegistry.select_credential(
               [entry],
               Map.put(selection_attrs(), :tenant_ref, "tenant://tenant-2")
             )
  end

  test "bounds categories, statuses, env states, and rejects raw material" do
    assert {:error, {:invalid_enum_value, :connector_category, :unknown, _allowed}} =
             valid_attrs()
             |> Map.put(:connector_category, :unknown)
             |> ConnectorRegistry.register()

    assert {:error, {:invalid_enum_value, :provider_account_status, :stale, _allowed}} =
             valid_attrs()
             |> Map.put(:provider_account_status, :stale)
             |> ConnectorRegistry.register()

    assert {:error, {:raw_material_rejected, forbidden}} =
             valid_attrs()
             |> Map.put(:raw_token, "secret")
             |> Map.put(:default_client, :global)
             |> ConnectorRegistry.register()

    assert Enum.sort(forbidden) == [:default_client, :raw_token]
  end

  defp selection_attrs do
    %{
      tenant_ref: "tenant://tenant-1",
      policy_revision_ref: "policy-revision://tenant-1/auth/1",
      provider_ref: "provider://github",
      provider_account_ref: "provider-account://tenant-1/github/account-a",
      connector_instance_ref: "connector-instance://tenant-1/github/rest-a",
      credential_handle_ref: "credential-handle://tenant-1/github/account-a/pat",
      target_ref: "target://tenant-1/http-client/a",
      operation_policy_ref: "operation-policy://tenant-1/github/rest"
    }
  end

  defp valid_attrs do
    %{
      tenant_ref: "tenant://tenant-1",
      policy_revision_ref: "policy-revision://tenant-1/auth/1",
      provider_ref: "provider://github",
      provider_family: "http",
      provider_account_ref: "provider-account://tenant-1/github/account-a",
      provider_account_status: :known,
      connector_ref: "connector://github/rest",
      connector_instance_ref: "connector-instance://tenant-1/github/rest-a",
      connector_category: :official_connector,
      credential_handle_ref: "credential-handle://tenant-1/github/account-a/pat",
      target_ref: "target://tenant-1/http-client/a",
      operation_policy_ref: "operation-policy://tenant-1/github/rest",
      owner_repo: "github_ex",
      package_path: "connectors/github",
      conformance_suite_ref: "conformance-suite://github/rest",
      env_remediation_state: :governed_clean,
      auth_methods: [:pat, :oauth, :installation_token],
      supported_operations: [:rest_request],
      binding_shape: %{requires_connector_binding_ref: true},
      product_boundary: %{governed_hot_path: true}
    }
  end
end
