defmodule Jido.Integration.V2.ConformanceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Conformance
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connector
  alias Jido.Integration.V2.Manifest

  defmodule BrokenSessionHandler do
    def run(_input, _context), do: {:ok, %{unexpected: true}}
  end

  defmodule BrokenSessionConnector do
    @behaviour Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "broken_session",
        capabilities: [
          Capability.new!(%{
            id: "broken.session.exec",
            connector: "broken_session",
            runtime_class: :session,
            kind: :session_operation,
            transport_profile: :stdio,
            handler: BrokenSessionHandler,
            metadata: %{
              required_scopes: ["session:execute"],
              policy: %{
                environment: %{allowed: [:prod]},
                sandbox: %{
                  level: :strict,
                  egress: :restricted,
                  approvals: :manual,
                  file_scope: "/srv/broken",
                  allowed_tools: ["broken.session.exec"]
                }
              }
            }
          })
        ]
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
        capabilities: [
          Capability.new!(%{
            id: "trigger.event.ingest",
            connector: "trigger_connector",
            runtime_class: :direct,
            kind: :trigger,
            transport_profile: :webhook,
            handler: TriggerHandler,
            metadata: %{
              required_scopes: ["trigger:ingest"],
              policy: %{
                environment: %{allowed: [:prod]},
                sandbox: %{
                  level: :standard,
                  egress: :restricted,
                  approvals: :auto,
                  allowed_tools: ["trigger.event.ingest"]
                }
              }
            }
          })
        ]
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

    assert Enum.map(report.suite_results, & &1.id) == [
             :manifest_contract,
             :capability_contracts,
             :runtime_class_fit,
             :policy_contract,
             :deterministic_fixtures,
             :ingress_definition_discipline
           ]

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

  test "returns an error for an unknown profile" do
    assert {:error, {:unknown_profile, :missing_profile}} =
             Conformance.run(GitHub, profile: :missing_profile)
  end
end
