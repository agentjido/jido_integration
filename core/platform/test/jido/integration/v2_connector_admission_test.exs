defmodule Jido.Integration.V2ConnectorAdmissionTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.ConnectorAdmissionEngine
  alias Jido.Integration.V2
  alias Jido.Integration.V2.Auth.Persistence, as: AuthPersistence
  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Connector
  alias Jido.Integration.V2.ControlPlane.RunLedger
  alias Jido.Integration.V2.ControlPlane.Persistence, as: ControlPlanePersistence
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec

  @control_plane_store_keys [
    :run_store,
    :attempt_store,
    :event_store,
    :artifact_store,
    :claim_check_store,
    :target_store,
    :ingress_store,
    :profile_registry_store
  ]
  @auth_store_keys [:credential_store, :lease_store, :connection_store, :install_store]

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
    previous_env = force_in_memory_stores!()
    reset_persistence!()
    V2.reset!()
    ConnectorAdmissionEngine.reset!()

    on_exit(fn ->
      reset_persistence!()
      restore_env(previous_env)
    end)

    :ok
  end

  defp force_in_memory_stores! do
    previous_env = %{
      control_plane: snapshot_keys(:jido_integration_v2_control_plane, @control_plane_store_keys),
      auth: snapshot_keys(:jido_integration_v2_auth, @auth_store_keys)
    }

    Enum.each(@control_plane_store_keys, fn key ->
      Application.put_env(:jido_integration_v2_control_plane, key, RunLedger)
    end)

    Enum.each(@auth_store_keys, fn key ->
      Application.put_env(:jido_integration_v2_auth, key, Jido.Integration.V2.Auth.Store)
    end)

    previous_env
  end

  defp reset_persistence! do
    ControlPlanePersistence.reset!()
    AuthPersistence.reset!()
    ControlPlanePersistence.configure!(profile: :mickey_mouse)
    AuthPersistence.configure!(profile: :mickey_mouse)
    :ok
  end

  defp snapshot_keys(app, keys) do
    Map.new(keys, fn key -> {key, Application.fetch_env(app, key)} end)
  end

  defp restore_env(previous_env) do
    restore_keys(:jido_integration_v2_control_plane, previous_env.control_plane)
    restore_keys(:jido_integration_v2_auth, previous_env.auth)
    :ok
  end

  defp restore_keys(app, snapshot) do
    Enum.each(snapshot, fn
      {key, {:ok, value}} -> Application.put_env(app, key, value)
      {key, :error} -> Application.delete_env(app, key)
    end)
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
