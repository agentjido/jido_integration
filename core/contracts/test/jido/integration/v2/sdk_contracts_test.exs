defmodule Jido.Integration.V2.SDKContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.CapabilityRef
  alias Jido.Integration.V2.ConformanceRef
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.ScopeRef

  defmodule SafeHandler do
    def run(_input, _context), do: {:ok, %{}}
  end

  test "SDK refs dump and load deterministically" do
    capability_ref =
      CapabilityRef.new!(%{
        connector_ref: "connector://tenant-1/acme",
        capability_id: "acme.issue.fetch",
        tenant_ref: "tenant://tenant-1",
        scope_ref: "scope://tenant-1/acme/read",
        contract_version: "connector-sdk.v1"
      })

    assert {:ok, ^capability_ref} = capability_ref |> CapabilityRef.dump() |> CapabilityRef.load()
    assert "sha256:" <> _digest = CapabilityRef.canonical_hash(capability_ref)

    scope_ref =
      ScopeRef.new!(%{
        scope_ref: "scope://tenant-1/acme/read",
        tenant_ref: "tenant://tenant-1",
        installation_ref: "installation://tenant-1/default",
        scope_class: "tenant_scoped",
        contract_version: "connector-sdk.v1"
      })

    assert {:ok, ^scope_ref} = scope_ref |> ScopeRef.dump() |> ScopeRef.load()

    conformance_ref =
      ConformanceRef.new!(%{
        conformance_ref: "conformance://tenant-1/acme",
        manifest_hash: "sha256:abc",
        contract_version: "connector-sdk.v1",
        profile: "external_companion",
        status: "passed",
        generated_at: "2026-05-05T00:00:00Z"
      })

    assert {:ok, ^conformance_ref} =
             conformance_ref |> ConformanceRef.dump() |> ConformanceRef.load()
  end

  test "manifest dump and hash are deterministic and SDK safe" do
    manifest = valid_external_manifest()
    dumped = Manifest.dump(manifest)

    assert {:ok, ^dumped} = Manifest.load_dump(dumped)
    assert Manifest.canonical_hash(manifest) == Manifest.canonical_hash(dumped)
    assert Manifest.external_safety_errors(manifest) == []
    assert dumped["contract_version"] == "connector-sdk.v1"
  end

  test "external safety review flags raw fields, missing tenant scope, and runtime internals" do
    manifest =
      valid_external_manifest(%{
        operations: [
          operation_attrs(%{
            handler: Jido.Integration.V2.ControlPlane,
            metadata: %{
              raw_secret: "secret",
              scope_posture: %{tenant_scope: :cross_tenant}
            }
          })
        ]
      })

    errors = Manifest.external_safety_errors(manifest)

    assert {:forbidden_manifest_key, "operations.0.metadata.raw_secret"} in errors
    assert {:unsafe_scope_posture, "acme.issue.fetch"} in errors

    assert {:runtime_internal_dependency, "acme.issue.fetch", "Jido.Integration.V2.ControlPlane"} in errors
  end

  test "manifest rejects unknown auth profile and duplicate operation id" do
    assert_raise ArgumentError, fn ->
      valid_external_manifest(%{auth: auth_attrs(%{default_profile: "missing_profile"})})
    end

    assert_raise ArgumentError, fn ->
      valid_external_manifest(%{operations: [operation_attrs(), operation_attrs()]})
    end
  end

  defp valid_external_manifest(overrides \\ %{}) do
    attrs =
      %{
        connector: "acme",
        auth: auth_attrs(),
        catalog: %{
          display_name: "Acme",
          description: "Acme SDK connector",
          category: "developer_tools",
          tags: ["acme"],
          docs_refs: [],
          maturity: :experimental,
          publication: :public
        },
        operations: [operation_attrs()],
        triggers: [],
        runtime_families: [:direct],
        metadata: %{contract_version: "connector-sdk.v1"}
      }
      |> Map.merge(overrides)

    Manifest.new!(attrs)
  end

  defp auth_attrs(overrides \\ %{}) do
    %{
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
          required_scopes: ["acme:read"],
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
      requested_scopes: ["acme:read"],
      durable_secret_fields: ["api_token"],
      lease_fields: ["api_token"],
      secret_names: []
    }
    |> Map.merge(overrides)
  end

  defp operation_attrs(overrides \\ %{}) do
    %{
      operation_id: "acme.issue.fetch",
      name: "issue_fetch",
      display_name: "Issue fetch",
      description: "Fetches one issue",
      runtime_class: :direct,
      transport_mode: :sdk,
      handler: SafeHandler,
      input_schema: Zoi.object(%{issue_id: Zoi.string()}),
      output_schema: Zoi.object(%{id: Zoi.string()}),
      permissions: %{required_scopes: ["acme:read"]},
      policy: %{
        environment: %{allowed: [:dev, :test]},
        sandbox: %{level: :standard, egress: :restricted, approvals: :auto, allowed_tools: []}
      },
      upstream: %{transport: :sdk},
      consumer_surface: %{
        mode: :connector_local,
        reason: "External companion SDK test stays package-local"
      },
      schema_policy: %{input: :defined, output: :defined},
      jido: %{},
      metadata: %{scope_posture: %{tenant_scope: :tenant_scoped}}
    }
    |> Map.merge(overrides)
  end
end
