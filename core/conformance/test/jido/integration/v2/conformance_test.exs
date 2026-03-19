defmodule Jido.Integration.V2.ConformanceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Conformance
  alias Jido.Integration.V2.Conformance.CheckResult
  alias Jido.Integration.V2.Connector
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.TriggerSpec

  defmodule BrokenSessionHandler do
    def run(_input, _context), do: {:ok, %{unexpected: true}}
  end

  defmodule BrokenSessionConnector do
    @behaviour Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "broken_session",
        auth: %{
          binding_kind: :connection_id,
          auth_type: :api_token,
          install: %{required: false},
          reauth: %{supported: false},
          requested_scopes: ["session:execute"],
          lease_fields: ["access_token"],
          secret_names: []
        },
        catalog: %{
          display_name: "Broken Session",
          description: "Broken conformance connector",
          category: "test",
          tags: ["broken"],
          docs_refs: [],
          maturity: :experimental,
          publication: :internal
        },
        operations: [
          %{
            operation_id: "broken.session.exec",
            name: "session_exec",
            display_name: "Broken session exec",
            description: "Exercises runtime fit failures",
            runtime_class: :session,
            transport_mode: :stdio,
            handler: BrokenSessionHandler,
            input_schema: Zoi.map(),
            output_schema: Zoi.map(),
            permissions: %{required_scopes: ["session:execute"]},
            runtime: %{},
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :strict,
                egress: :restricted,
                approvals: :manual,
                file_scope: "/srv/broken",
                allowed_tools: ["broken.session.exec"]
              }
            },
            upstream: %{protocol: :stdio},
            jido: %{action: %{name: "broken_session_exec"}}
          }
        ],
        triggers: [],
        runtime_families: [:session]
      })
    end
  end

  defmodule TriggerHandler do
    def run(_input, _context), do: {:ok, %{accepted: true}}
  end

  defmodule TriggerConnector do
    @behaviour Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "trigger_connector",
        auth: %{
          binding_kind: :connection_id,
          auth_type: :api_token,
          install: %{required: false},
          reauth: %{supported: false},
          requested_scopes: ["trigger:ingest"],
          lease_fields: ["token"],
          secret_names: ["webhook_secret"]
        },
        catalog: %{
          display_name: "Trigger Connector",
          description: "Webhook conformance connector",
          category: "test",
          tags: ["trigger"],
          docs_refs: [],
          maturity: :experimental,
          publication: :internal
        },
        operations: [],
        triggers: [
          %{
            trigger_id: "trigger.event.ingest",
            name: "event_ingest",
            display_name: "Event ingest",
            description: "Accepts a webhook payload",
            runtime_class: :direct,
            delivery_mode: :webhook,
            handler: TriggerHandler,
            config_schema: Zoi.map(),
            signal_schema: Zoi.map(),
            permissions: %{required_scopes: ["trigger:ingest"]},
            checkpoint: %{strategy: :cursor},
            dedupe: %{strategy: :event_id},
            verification: %{secret_name: "webhook_secret"},
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: ["trigger.event.ingest"]
              }
            },
            jido: %{sensor: %{name: "trigger_event_ingest"}}
          }
        ],
        runtime_families: [:direct]
      })
    end
  end

  defmodule TriggerConnector.Conformance do
    def fixtures do
      [
        %{
          capability_id: "trigger.event.ingest",
          input: %{},
          credential_ref: %{id: "cred-trigger-1", subject: "router", scopes: ["trigger:ingest"]},
          credential_lease: %{
            lease_id: "lease-trigger-1",
            credential_ref_id: "cred-trigger-1",
            subject: "router",
            scopes: ["trigger:ingest"],
            payload: %{token: "lease-token"},
            issued_at: ~U[2026-03-12 00:00:00Z],
            expires_at: ~U[2026-03-12 00:05:00Z]
          },
          expect: %{
            output: %{accepted: true},
            event_types: ["attempt.started", "attempt.completed"]
          }
        }
      ]
    end
  end

  defmodule DriftedAuthConnector do
    @behaviour Connector

    @operation OperationSpec.new!(%{
                 operation_id: "drifted.issue.write",
                 name: "issue_write",
                 runtime_class: :direct,
                 transport_mode: :sdk,
                 handler: TriggerHandler,
                 input_schema: Zoi.map(),
                 output_schema: Zoi.map(),
                 permissions: %{required_scopes: ["issues:write"]},
                 policy: %{
                   environment: %{allowed: [:prod]},
                   sandbox: %{
                     level: :standard,
                     egress: :restricted,
                     approvals: :auto,
                     allowed_tools: ["drifted.issue.write"]
                   }
                 },
                 upstream: %{method: "POST", path: "/issues"},
                 jido: %{action: %{name: "drifted_issue_write"}}
               })

    @trigger TriggerSpec.new!(%{
               trigger_id: "drifted.issue.updated",
               name: "issue_updated",
               runtime_class: :direct,
               delivery_mode: :webhook,
               handler: TriggerHandler,
               config_schema: Zoi.map(),
               signal_schema: Zoi.map(),
               permissions: %{required_scopes: ["issues:admin"]},
               checkpoint: %{strategy: :cursor},
               dedupe: %{strategy: :event_id},
               verification: %{secret_name: "webhook_secret"},
               secret_requirements: ["signing_secret"],
               jido: %{sensor: %{name: "drifted_issue_updated"}}
             })

    @impl true
    def manifest do
      %Manifest{
        connector: "drifted_auth",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :oauth2,
            install: %{required: true},
            reauth: %{supported: true},
            requested_scopes: ["issues:read"],
            lease_fields: ["access_token"],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "Drifted Auth",
            description: "Connector that bypasses manifest normalization",
            category: "test",
            tags: ["drift"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [@operation],
        triggers: [@trigger],
        runtime_families: [:direct],
        capabilities:
          [
            Capability.from_operation!("drifted_auth", @operation),
            Capability.from_trigger!("drifted_auth", @trigger)
          ]
          |> Enum.sort_by(& &1.id),
        metadata: %{}
      }
    end
  end

  test "returns the stable connector foundation profile names" do
    assert Conformance.profiles() == [:connector_foundation]
  end

  test "passes the GitHub connector with stable suite ids and statuses" do
    assert {:ok, report} =
             Conformance.run(
               GitHub,
               profile: :connector_foundation,
               generated_at: ~U[2026-03-12 00:00:00Z]
             )

    assert report.status == :passed

    manifest_suite = Enum.find(report.suite_results, &(&1.id == :manifest_contract))
    capability_suite = Enum.find(report.suite_results, &(&1.id == :capability_contracts))

    assert Enum.map(report.suite_results, & &1.id) == [
             :manifest_contract,
             :capability_contracts,
             :runtime_class_fit,
             :policy_contract,
             :deterministic_fixtures,
             :ingress_definition_discipline
           ]

    assert manifest_suite.status == :passed
    assert capability_suite.status == :passed
    assert Enum.find(report.suite_results, &(&1.id == :deterministic_fixtures)).status == :passed

    assert Enum.find(report.suite_results, &(&1.id == :ingress_definition_discipline)).status ==
             :skipped
  end

  test "reports runtime fit and fixture failures for a broken connector" do
    assert {:ok, report} =
             Conformance.run(
               BrokenSessionConnector,
               profile: :connector_foundation,
               generated_at: ~U[2026-03-12 00:00:00Z]
             )

    runtime_suite = Enum.find(report.suite_results, &(&1.id == :runtime_class_fit))
    fixture_suite = Enum.find(report.suite_results, &(&1.id == :deterministic_fixtures))

    assert report.status == :failed
    assert runtime_suite.status == :failed
    assert fixture_suite.status == :failed

    assert Enum.any?(runtime_suite.checks, fn check ->
             check.id == "broken.session.exec.runtime_driver_declared"
           end)

    assert Enum.any?(runtime_suite.checks, fn check ->
             check.id == "broken.session.exec.runtime_contract"
           end)

    assert Enum.any?(fixture_suite.checks, fn check ->
             check.id == "fixtures.present"
           end)
  end

  test "requires ingress definitions when a trigger capability is declared" do
    assert {:ok, report} =
             Conformance.run(
               TriggerConnector,
               profile: :connector_foundation,
               generated_at: ~U[2026-03-12 00:00:00Z]
             )

    ingress_suite = Enum.find(report.suite_results, &(&1.id == :ingress_definition_discipline))

    assert ingress_suite.status == :failed

    assert Enum.any?(ingress_suite.checks, fn check ->
             check.id == "ingress.definitions.present"
           end)
  end

  test "flags auth scope and trigger secret drift in manifest conformance" do
    assert {:ok, report} =
             Conformance.run(
               DriftedAuthConnector,
               profile: :connector_foundation,
               generated_at: ~U[2026-03-12 00:00:00Z]
             )

    manifest_suite = Enum.find(report.suite_results, &(&1.id == :manifest_contract))

    assert manifest_suite.status == :failed

    assert failed_check?(manifest_suite.checks, "manifest.auth.requested_scopes.cover_required")

    assert failed_check?(
             manifest_suite.checks,
             "manifest.auth.secret_names.cover_trigger_secrets"
           )
  end

  test "returns an error for an unknown profile" do
    assert {:error, {:unknown_profile, :missing_profile}} =
             Conformance.run(GitHub, profile: :missing_profile)
  end

  defp failed_check?(checks, id) do
    Enum.any?(checks, fn
      %CheckResult{id: ^id, status: :failed} -> true
      _check -> false
    end)
  end
end
