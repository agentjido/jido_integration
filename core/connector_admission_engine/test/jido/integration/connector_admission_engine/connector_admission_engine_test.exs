defmodule Jido.Integration.ConnectorAdmissionEngineTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.ConnectorAdmissionEngine
  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec

  defmodule Handler do
    def run(_input, _context), do: {:ok, %{}}
  end

  setup do
    ConnectorAdmissionEngine.reset!()
    :ok
  end

  test "admits an explicit companion connector into the memory-default store" do
    manifest = manifest()
    conformance = conformance(manifest)

    assert {:ok, record} =
             ConnectorAdmissionEngine.admit(manifest,
               tenant_ref: "tenant://tenant-1",
               app_config: %{tenant_ref: "tenant://tenant-1", app_config_ref: "app-config://e"},
               conformance: conformance,
               persistence_profile: "memory-default",
               trace_ref: "trace://e",
               release_manifest_ref: "release://phase-e"
             )

    assert record.admission_status == :admitted
    assert record.operation_count == 1
    assert record.trigger_count == 0
    assert record.auth_profiles == ["default_manual_secret"]
    assert record.scopes == ["safe:run"]
    assert ConnectorAdmissionEngine.records() == [record]
  end

  test "rejects missing conformance and duplicate capability ids" do
    manifest = manifest()

    assert {:error, missing} =
             ConnectorAdmissionEngine.admit(manifest,
               tenant_ref: "tenant://tenant-1",
               app_config: %{tenant_ref: "tenant://tenant-1"}
             )

    assert missing.admission_status == :rejected_missing_conformance

    assert {:error, duplicate} =
             ConnectorAdmissionEngine.admit(manifest,
               tenant_ref: "tenant://tenant-1",
               app_config: %{tenant_ref: "tenant://tenant-1"},
               conformance: conformance(manifest),
               existing_capability_ids: ["safe_companion.sample.perform"]
             )

    assert duplicate.admission_status == :rejected_duplicate_capability
    assert duplicate.duplicate_capabilities == ["safe_companion.sample.perform"]
  end

  test "accepts built-in mickey mouse persistence without a durable adapter" do
    manifest = manifest()

    assert {:ok, record} =
             ConnectorAdmissionEngine.admit(manifest,
               tenant_ref: "tenant://tenant-1",
               app_config: %{tenant_ref: "tenant://tenant-1"},
               conformance: conformance(manifest),
               persistence_profile: :mickey_mouse
             )

    assert record.persistence_profile == :mickey_mouse
    assert record.admission_status == :admitted
  end

  test "rejects unsafe scopes, tenant mismatch, contract mismatch, and unregistered durable store" do
    unsafe_manifest =
      manifest(operation_metadata: %{scope_posture: %{tenant_scope: :cross_tenant}})

    assert {:error, unsafe} =
             ConnectorAdmissionEngine.admit(unsafe_manifest,
               tenant_ref: "tenant://tenant-1",
               app_config: %{tenant_ref: "tenant://tenant-1"},
               conformance: conformance(unsafe_manifest)
             )

    assert unsafe.admission_status == :rejected_unsafe_scope

    valid_manifest = manifest()

    assert {:error, tenant_mismatch} =
             ConnectorAdmissionEngine.admit(valid_manifest,
               tenant_ref: "tenant://tenant-1",
               app_config: %{tenant_ref: "tenant://tenant-2"},
               conformance: conformance(valid_manifest)
             )

    assert tenant_mismatch.admission_status == :rejected_tenant_mismatch

    mismatch_conformance =
      valid_manifest
      |> conformance()
      |> Map.put(:contract_version, "old")

    assert {:error, contract_mismatch} =
             ConnectorAdmissionEngine.admit(valid_manifest,
               tenant_ref: "tenant://tenant-1",
               app_config: %{tenant_ref: "tenant://tenant-1"},
               conformance: mismatch_conformance
             )

    assert contract_mismatch.admission_status == :rejected_missing_conformance

    assert {:error, durable} =
             ConnectorAdmissionEngine.admit(valid_manifest,
               tenant_ref: "tenant://tenant-1",
               app_config: %{tenant_ref: "tenant://tenant-1"},
               conformance: conformance(valid_manifest),
               persistence_profile: "postgres://connector-admission"
             )

    assert durable.admission_status == :rejected_durable_adapter
  end

  test "rejects manifest collision after an admitted record exists" do
    manifest = manifest()

    assert {:ok, _record} =
             ConnectorAdmissionEngine.admit(manifest,
               tenant_ref: "tenant://tenant-1",
               app_config: %{tenant_ref: "tenant://tenant-1"},
               conformance: conformance(manifest)
             )

    changed_manifest = manifest(operation_display_name: "Changed")

    assert {:error, collision} =
             ConnectorAdmissionEngine.admit(changed_manifest,
               tenant_ref: "tenant://tenant-1",
               app_config: %{tenant_ref: "tenant://tenant-1"},
               conformance: conformance(changed_manifest)
             )

    assert collision.admission_status == :rejected_manifest_collision
  end

  defp conformance(manifest) do
    %{
      status: "passed",
      manifest_hash: Manifest.canonical_hash(manifest),
      contract_version: Manifest.contract_version(manifest)
    }
  end

  defp manifest(opts \\ []) do
    operation_metadata =
      Keyword.get(opts, :operation_metadata, %{scope_posture: %{tenant_scope: :tenant_scoped}})

    display_name = Keyword.get(opts, :operation_display_name, "Sample perform")

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
          description: "Safe companion proof connector",
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
          display_name: display_name,
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
          consumer_surface: %{mode: :connector_local, reason: "External proof stays local"},
          schema_policy: %{input: :defined, output: :defined},
          jido: %{},
          metadata: operation_metadata
        })
      ],
      triggers: [],
      runtime_families: [:direct],
      metadata: %{contract_version: "connector-sdk.v1"}
    })
  end
end
