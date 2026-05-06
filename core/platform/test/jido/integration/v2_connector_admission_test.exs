defmodule Jido.Integration.V2ConnectorAdmissionTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.ConnectorAdmissionEngine
  alias Jido.Integration.V2
  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Connector
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec

  defmodule Handler do
    def run(_input, _context), do: {:ok, %{}}
  end

  defmodule CompanionConnector do
    @behaviour Connector

    def manifest do
      Manifest.new!(%{
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
            description: "Safe companion connector",
            category: "developer_tools",
            tags: ["safe"],
            docs_refs: [],
            maturity: :experimental,
            publication: :public
          }),
        operations: [
          OperationSpec.new!(%{
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
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: []
              }
            },
            upstream: %{transport: :sdk},
            consumer_surface: %{mode: :connector_local, reason: "External companion"},
            schema_policy: %{input: :defined, output: :defined},
            jido: %{},
            metadata: %{scope_posture: %{tenant_scope: :tenant_scoped}}
          })
        ],
        triggers: [],
        runtime_families: [:direct],
        metadata: %{contract_version: "connector-sdk.v1"}
      })
    end
  end

  setup do
    V2.reset!()
    ConnectorAdmissionEngine.reset!()
    :ok
  end

  test "admits companion connectors only from explicit app config candidates" do
    [candidate] =
      V2.companion_connector_candidates([
        %{
          module: CompanionConnector,
          package: :safe_companion,
          tenant_ref: "tenant://tenant-1",
          app_config_ref: "app-config://tenant-1/safe-companion"
        }
      ])

    manifest = CompanionConnector.manifest()

    assert {:ok, record} =
             V2.admit_connector(candidate.module,
               tenant_ref: candidate.tenant_ref,
               app_config: candidate,
               conformance: %{
                 status: "passed",
                 manifest_hash: Manifest.canonical_hash(manifest),
                 contract_version: Manifest.contract_version(manifest)
               }
             )

    assert record.admission_status == :admitted
    assert V2.companion_auto_discovery?() == false
  end

  test "ignores malformed companion config candidates" do
    assert V2.companion_connector_candidates([
             %{module: "CompanionConnector", package: :safe_companion},
             %{module: CompanionConnector, tenant_ref: "tenant://tenant-1"}
           ]) == []
  end
end
