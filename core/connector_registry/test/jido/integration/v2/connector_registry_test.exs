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

  test "admits generated and companion SDK lanes with ref-only metadata" do
    entries =
      [
        generated_attrs(:github_ex, "github_ex", "github", "http", :generated_sdk_client, [
          :classic_pat,
          :fine_grained_pat,
          :installation_token,
          :oauth_user_token
        ]),
        generated_attrs(:notion_sdk, "notion_sdk", "notion", "http", :generated_sdk_client, [
          :bearer,
          :oauth
        ]),
        generated_attrs(:linear_sdk, "linear_sdk", "linear", "graphql", :generated_sdk_client, [
          :api_token,
          :oauth_app_user
        ]),
        generated_attrs(
          :pristine,
          "apps/pristine_runtime",
          "http",
          "http",
          :companion_connector,
          [
            :bearer,
            :oauth_token_source
          ]
        ),
        generated_attrs(
          :prismatic,
          "apps/prismatic_runtime",
          "graphql",
          "graphql",
          :companion_connector,
          [:api_token, :oauth_app_user]
        )
      ]
      |> Enum.map(fn attrs ->
        assert {:ok, entry} = ConnectorRegistry.register(attrs)
        entry
      end)

    assert Enum.map(entries, & &1.owner_repo) == [
             "github_ex",
             "notion_sdk",
             "linear_sdk",
             "pristine",
             "prismatic"
           ]

    assert Enum.all?(entries, fn entry ->
             assert {:ok, receipt} = ConnectorRegistry.companion_admission(entry)

             receipt.credential_handle_ref == entry.credential_handle_ref and
               receipt.conformance_suite_ref == entry.conformance_suite_ref and
               receipt.binding_shape.requires_connector_binding_ref
           end)
  end

  test "generated SDK lane can upgrade to official connector without changing identity refs" do
    assert {:ok, generated} =
             :github_ex
             |> generated_attrs("github_ex", "github", "http", :generated_sdk_client, [
               :classic_pat
             ])
             |> ConnectorRegistry.register()

    assert {:ok, official} =
             ConnectorRegistry.upgrade_to_official(generated,
               connector_ref: "connector://github/official-rest",
               package_path: "connectors/github",
               conformance_suite_ref: "conformance-suite://github/official-rest"
             )

    assert official.connector_category == :official_connector
    assert official.connector_ref == "connector://github/official-rest"
    assert ConnectorRegistry.identity_key(official) == ConnectorRegistry.identity_key(generated)
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

  defp generated_attrs(owner, package_path, provider, family, category, auth_methods) do
    provider_name = Atom.to_string(owner)

    %{
      tenant_ref: "tenant://tenant-1",
      policy_revision_ref: "policy-revision://tenant-1/auth/1",
      provider_ref: "provider://#{provider}",
      provider_family: family,
      provider_account_ref: "provider-account://tenant-1/#{provider}/default",
      provider_account_status: :known,
      connector_ref: "connector://#{provider_name}/generated-sdk",
      connector_instance_ref: "connector-instance://tenant-1/#{provider_name}/generated-sdk",
      connector_category: category,
      credential_handle_ref: "credential-handle://tenant-1/#{provider}/default",
      target_ref: "target://tenant-1/#{provider}/default",
      operation_policy_ref: "operation-policy://tenant-1/#{provider}/default",
      owner_repo: provider_name,
      package_path: package_path,
      conformance_suite_ref: "conformance-suite://#{provider_name}/generated-sdk",
      env_remediation_state: :governed_clean,
      auth_methods: auth_methods,
      supported_operations: [:governed_request],
      target_refs: ["target://tenant-1/#{provider}/default"],
      credential_handle_refs: ["credential-handle://tenant-1/#{provider}/default"],
      binding_shape: %{requires_connector_binding_ref: true},
      product_boundary: %{governed_hot_path: true, companion_lane: true}
    }
  end
end
