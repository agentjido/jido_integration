defmodule Jido.Integration.V2.ProviderFeatureMatrixTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.ConnectorRegistry
  alias Jido.Integration.V2.ProviderFeatureMatrix

  test "every in-play provider has every required placement column" do
    for row <- ProviderFeatureMatrix.rows() do
      assert Enum.sort(Map.keys(row.features)) == Enum.sort(ProviderFeatureMatrix.columns())

      for placement <- Map.values(row.features) do
        assert placement in ProviderFeatureMatrix.placements()
      end
    end

    assert :codex in ProviderFeatureMatrix.providers()
    assert :github in ProviderFeatureMatrix.providers()
    assert :reqllm_next in ProviderFeatureMatrix.providers()
    assert :self_hosted_inference in ProviderFeatureMatrix.providers()
  end

  test "unsupported and forbidden feature requests fail before provider effects" do
    assert {:error, {:unsupported_feature, :github, :streaming}} =
             ProviderFeatureMatrix.authorize_feature(:github, :streaming)

    assert {:error, {:forbidden_feature, :linear, :shell_execution}} =
             ProviderFeatureMatrix.authorize_feature("linear", "shell_execution")

    assert :ok = ProviderFeatureMatrix.authorize_feature(:codex, :native_cli_login)
    assert :ok = ProviderFeatureMatrix.authorize_feature(:reqllm_next, :streaming)
  end

  test "unknown providers and features fail closed" do
    assert {:error, {:unknown_provider, :unknown}} = ProviderFeatureMatrix.row(:unknown)

    assert {:error, {:unknown_feature, :unknown_feature}} =
             ProviderFeatureMatrix.placement(:codex, :unknown_feature)
  end

  test "registry entries validate against matrix family and connector categories" do
    assert {:ok, entry} = ConnectorRegistry.register(registry_attrs())
    assert :ok = ProviderFeatureMatrix.validate_registry_entry(entry)

    mismatched = %{entry | provider_family: "graphql"}

    assert {:error, {:provider_family_mismatch, "graphql", "http"}} =
             ProviderFeatureMatrix.validate_registry_entry(mismatched)

    invalid_category = %{entry | connector_category: :unknown}

    assert {:error, {:unknown_connector_category, :unknown}} =
             ProviderFeatureMatrix.validate_registry_entry(invalid_category)
  end

  test "docs rows are bounded maps without raw credential fields" do
    rows = ProviderFeatureMatrix.docs_rows()

    assert Enum.all?(rows, &Map.has_key?(&1, :features))
    refute inspect(rows) =~ "raw_token"
    refute inspect(rows) =~ "authorization_header"
  end

  defp registry_attrs do
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
      supported_operations: [:rest_request]
    }
  end
end
