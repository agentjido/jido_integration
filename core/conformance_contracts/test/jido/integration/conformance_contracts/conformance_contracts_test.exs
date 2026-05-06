defmodule Jido.Integration.ConformanceContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.ConformanceContracts
  alias Jido.Integration.V2.Connector
  alias Jido.Integration.V2.Manifest

  defmodule Handler do
    def run(_input, _context), do: {:ok, %{}}
  end

  defmodule Fixture do
    alias Jido.Integration.ConformanceContractsTest.Handler
    alias Jido.Integration.V2.AuthSpec
    alias Jido.Integration.V2.CatalogSpec
    alias Jido.Integration.V2.OperationSpec

    def base_manifest do
      %{
        connector: "safe_companion",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            supported_profiles: [
              %{
                id: "default_manual_secret",
                auth_type: :api_token,
                subject_kind: :user,
                install_required: false,
                durable_secret_fields: ["api_token"],
                lease_fields: ["api_token"],
                management_modes: [:external_secret, :manual],
                required_scopes: ["safe:run"],
                grant_types: [:manual_token],
                callback_required: false,
                pkce_required: false,
                refresh_supported: false,
                revoke_supported: false,
                reauth_supported: false,
                external_secret_supported: true,
                external_secret_lease_fields: [],
                docs_refs: [],
                metadata: %{}
              }
            ],
            default_profile: "default_manual_secret",
            install: %{required: false},
            reauth: %{supported: false},
            management_modes: [:external_secret, :manual],
            requested_scopes: ["safe:run"],
            durable_secret_fields: ["api_token"],
            lease_fields: ["api_token"],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "Safe Companion",
            description: "Safe companion proof connector",
            category: "developer_tools",
            tags: ["safe"],
            docs_refs: [],
            maturity: :experimental,
            publication: :public
          }),
        operations: [operation_attrs()],
        triggers: [],
        runtime_families: [:direct],
        metadata: %{contract_version: "connector-sdk.v1"}
      }
    end

    def operation_attrs(overrides \\ %{}) do
      %{
        operation_id: "safe_companion.sample.perform",
        name: "sample_perform",
        runtime_class: :direct,
        transport_mode: :sdk,
        handler: Handler,
        input_schema: Zoi.object(%{message: Zoi.string()}),
        output_schema: Zoi.object(%{message: Zoi.string()}),
        permissions: %{required_scopes: ["safe:run"]},
        policy: %{
          environment: %{allowed: [:dev, :test]},
          sandbox: %{level: :standard, egress: :restricted, approvals: :auto, allowed_tools: []}
        },
        upstream: %{transport: :sdk},
        consumer_surface: %{mode: :connector_local, reason: "External proof stays local"},
        schema_policy: %{input: :defined, output: :defined},
        jido: %{},
        metadata: %{scope_posture: %{tenant_scope: :tenant_scoped}}
      }
      |> Map.merge(overrides)
      |> OperationSpec.new!()
    end
  end

  defmodule SafeConnector do
    @behaviour Connector

    def manifest do
      Manifest.new!(Fixture.base_manifest())
    end
  end

  defmodule MissingVersionConnector do
    @behaviour Connector

    def manifest do
      Manifest.new!(Map.put(Fixture.base_manifest(), :metadata, %{}))
    end
  end

  defmodule UnsafeScopeConnector do
    @behaviour Connector

    def manifest do
      operation =
        Fixture.operation_attrs(%{
          metadata: %{scope_posture: %{tenant_scope: :cross_tenant}}
        })

      Manifest.new!(%{Fixture.base_manifest() | operations: [operation]})
    end
  end

  test "passes a safe external companion connector" do
    assert {:ok, report} = ConformanceContracts.validate(SafeConnector)
    assert report.connector == "safe_companion"
    assert report.capability_ids == ["safe_companion.sample.perform"]
  end

  test "fails missing manifest version" do
    assert {:error, errors} = ConformanceContracts.validate(MissingVersionConnector)
    assert :missing_manifest_version in errors
  end

  test "fails unsafe scope posture" do
    assert {:error, errors} = ConformanceContracts.validate(UnsafeScopeConnector)
    assert Enum.any?(errors, &external_safety_error?/1)
  end

  defp external_safety_error?({:external_safety_errors, safety_errors}) do
    {:unsafe_scope_posture, "safe_companion.sample.perform"} in safety_errors
  end

  defp external_safety_error?(_other), do: false
end
