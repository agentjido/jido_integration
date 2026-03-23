defmodule Jido.Integration.V2.ConformanceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Conformance
  alias Jido.Integration.V2.Conformance.CheckResult
  alias Jido.Integration.V2.Conformance.Suites.RuntimeClassFit
  alias Jido.Integration.V2.Connector
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.TriggerSpec

  defmodule BrokenSessionHandler do
    def run(_input, _context), do: {:ok, %{unexpected: true}}
  end

  defmodule HarnessBackedStreamHandler do
  end

  defmodule HarnessBackedStreamConnector do
    @behaviour Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "harness_backed_stream",
        auth: %{
          binding_kind: :connection_id,
          auth_type: :api_token,
          install: %{required: false},
          reauth: %{supported: false},
          requested_scopes: ["stream:execute"],
          lease_fields: ["access_token"],
          secret_names: []
        },
        catalog: %{
          display_name: "Harness Backed Stream",
          description: "Harness-targeted stream connector",
          category: "test",
          tags: ["stream"],
          docs_refs: [],
          maturity: :experimental,
          publication: :internal
        },
        operations: [
          %{
            operation_id: "harness.stream.exec",
            name: "stream_exec",
            display_name: "Harness stream exec",
            description: "Exercises Harness-backed runtime fit",
            runtime_class: :stream,
            transport_mode: :stdio,
            handler: HarnessBackedStreamHandler,
            input_schema:
              Zoi.object(%{
                prompt: Zoi.string()
              }),
            output_schema:
              Zoi.object(%{
                rows: Zoi.list(Zoi.map())
              }),
            permissions: %{required_scopes: ["stream:execute"]},
            runtime: %{
              driver: "asm",
              provider: :claude,
              options: %{}
            },
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: ["harness.stream.exec"]
              }
            },
            upstream: %{transport: :stdio},
            consumer_surface: %{
              mode: :common,
              normalized_id: "market.ticks.pull",
              action_name: "market_ticks_pull"
            },
            schema_policy: %{input: :defined, output: :defined},
            jido: %{action: %{name: "market_ticks_pull"}},
            metadata: %{
              runtime_family: %{
                session_affinity: :target,
                resumable: false,
                approval_required: false,
                stream_capable: true,
                lifecycle_owner: :asm,
                runtime_ref: :session
              }
            }
          }
        ],
        triggers: [],
        runtime_families: [:stream]
      })
    end
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
            consumer_surface: %{
              mode: :connector_local,
              reason: "Session runtime proofs stay connector-local in conformance"
            },
            schema_policy: %{
              input: :passthrough,
              output: :passthrough,
              justification:
                "Runtime-fit conformance keeps this session proof connector connector-local"
            },
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
            consumer_surface: %{
              mode: :connector_local,
              reason: "Trigger delivery stays above the connector package"
            },
            schema_policy: %{
              config: :passthrough,
              signal: :passthrough,
              justification: "Ingress conformance keeps this trigger connector connector-local"
            },
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

  defmodule TriggerIdentityDriftConnector do
    @behaviour Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "trigger_identity_drift",
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
          display_name: "Trigger Identity Drift",
          description: "Webhook conformance connector with drifted ingress evidence",
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
            consumer_surface: %{
              mode: :connector_local,
              reason: "Trigger delivery stays above the connector package"
            },
            schema_policy: %{
              config: :passthrough,
              signal: :passthrough,
              justification: "Ingress conformance keeps this trigger connector connector-local"
            },
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: ["trigger.event.ingest"]
              }
            },
            jido: %{
              sensor: %{
                name: "trigger_event_ingest",
                signal_type: "trigger.event.accepted",
                signal_source: "/ingress/webhook/trigger/event.accepted"
              }
            }
          }
        ],
        runtime_families: [:direct]
      })
    end
  end

  defmodule TriggerIdentityDriftConnector.Conformance do
    def fixtures do
      [
        %{
          capability_id: "trigger.event.ingest",
          input: %{},
          credential_ref: %{
            id: "cred-trigger-identity-1",
            subject: "router",
            scopes: ["trigger:ingest"]
          },
          credential_lease: %{
            lease_id: "lease-trigger-identity-1",
            credential_ref_id: "cred-trigger-identity-1",
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

    def ingress_definitions do
      [
        %{
          source: :webhook,
          connector_id: "trigger_identity_drift",
          trigger_id: "drifted.trigger.id",
          capability_id: "trigger.event.ingest",
          signal_type: "drifted.signal.type",
          signal_source: "/ingress/webhook/drifted/source",
          verification: %{
            algorithm: :sha256,
            secret: "drifted-secret",
            signature_header: "x-signature"
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
                 input_schema:
                   Zoi.object(%{
                     issue_id: Zoi.string()
                   }),
                 output_schema:
                   Zoi.object(%{
                     issue_id: Zoi.string()
                   }),
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
                 consumer_surface: %{
                   mode: :common,
                   normalized_id: "work_item.update",
                   action_name: "work_item_update"
                 },
                 schema_policy: %{input: :defined, output: :defined},
                 jido: %{action: %{name: "drifted_issue_write"}}
               })

    @trigger TriggerSpec.new!(%{
               trigger_id: "drifted.issue.updated",
               name: "issue_updated",
               runtime_class: :direct,
               delivery_mode: :webhook,
               handler: TriggerHandler,
               config_schema:
                 Zoi.object(%{
                   webhook_secret: Zoi.string()
                 }),
               signal_schema:
                 Zoi.object(%{
                   issue_id: Zoi.string()
                 }),
               permissions: %{required_scopes: ["issues:admin"]},
               checkpoint: %{strategy: :cursor},
               dedupe: %{strategy: :event_id},
               verification: %{secret_name: "webhook_secret"},
               secret_requirements: ["signing_secret"],
               consumer_surface: %{
                 mode: :connector_local,
                 reason: "Webhook delivery stays above the connector package"
               },
               schema_policy: %{config: :defined, signal: :defined},
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

  defmodule ProjectedPlaceholderConnector do
    @behaviour Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "projected_placeholder",
        auth: %{
          binding_kind: :connection_id,
          auth_type: :oauth2,
          install: %{required: true},
          reauth: %{supported: true},
          requested_scopes: ["issues:read"],
          lease_fields: ["access_token"],
          secret_names: []
        },
        catalog: %{
          display_name: "Projected Placeholder",
          description: "Connector with an invalid projected common surface schema policy",
          category: "test",
          tags: ["projection"],
          docs_refs: [],
          maturity: :experimental,
          publication: :internal
        },
        operations: [
          %{
            operation_id: "projected_placeholder.issue.fetch",
            name: "issue_fetch",
            display_name: "Issue fetch",
            description: "Uses passthrough schemas even though it is projected",
            runtime_class: :direct,
            transport_mode: :sdk,
            handler: TriggerHandler,
            input_schema: Zoi.map(),
            output_schema: Zoi.map(),
            permissions: %{required_scopes: ["issues:read"]},
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: ["projected_placeholder.issue.fetch"]
              }
            },
            upstream: %{method: "GET", path: "/issues/{issue_id}"},
            consumer_surface: %{
              mode: :common,
              normalized_id: "work_item.fetch",
              action_name: "work_item_fetch"
            },
            schema_policy: %{
              input: :passthrough,
              output: :passthrough,
              justification:
                "This should fail because projected common surfaces need real schemas"
            },
            jido: %{}
          }
        ],
        triggers: [],
        runtime_families: [:direct]
      })
    end
  end

  defmodule DeferredPassthroughConnector do
    @behaviour Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "deferred_passthrough",
        auth: %{
          binding_kind: :connection_id,
          auth_type: :oauth2,
          install: %{required: true},
          reauth: %{supported: true},
          requested_scopes: ["provider:raw"],
          lease_fields: ["access_token"],
          secret_names: []
        },
        catalog: %{
          display_name: "Deferred Passthrough",
          description:
            "Connector-local runtime operation with explicit passthrough schema justification",
          category: "test",
          tags: ["projection"],
          docs_refs: [],
          maturity: :experimental,
          publication: :internal
        },
        operations: [
          %{
            operation_id: "deferred_passthrough.provider.raw_lookup",
            name: "provider_raw_lookup",
            display_name: "Provider raw lookup",
            description:
              "A connector-local operation that intentionally stays out of the common consumer surface",
            runtime_class: :direct,
            transport_mode: :sdk,
            handler: TriggerHandler,
            input_schema: Zoi.map(),
            output_schema: Zoi.map(),
            permissions: %{required_scopes: ["provider:raw"]},
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: ["deferred_passthrough.provider.raw_lookup"]
              }
            },
            upstream: %{method: "GET", path: "/provider/raw_lookup"},
            consumer_surface: %{
              mode: :connector_local,
              reason:
                "Provider-specific long-tail methods are available through the connector boundary only"
            },
            schema_policy: %{
              input: :passthrough,
              output: :passthrough,
              justification:
                "Connector-local passthrough while this runtime slice remains outside the normalized common consumer surface"
            },
            jido: %{}
          }
        ],
        triggers: [],
        runtime_families: [:direct]
      })
    end
  end

  defmodule ProjectedTriggerSignalMetadataDriftConnector do
    @behaviour Connector

    @trigger struct!(TriggerSpec, %{
               trigger_id: "projected_trigger_signal_metadata.market.tick.detected",
               name: "market_tick_detected",
               display_name: "Market tick detected",
               description: "Projected trigger missing deterministic signal metadata",
               runtime_class: :direct,
               delivery_mode: :poll,
               handler: TriggerHandler,
               config_schema:
                 Zoi.object(%{
                   interval_ms: Zoi.integer() |> Zoi.default(60_000)
                 }),
               signal_schema:
                 Zoi.object(%{
                   symbol: Zoi.string(),
                   price: Zoi.number()
                 }),
               permissions: %{required_scopes: ["market:read"]},
               checkpoint: %{strategy: :cursor},
               dedupe: %{strategy: :event_id},
               verification: %{},
               policy: %{},
               consumer_surface: %{
                 mode: :common,
                 normalized_id: "market.ticks.detected",
                 sensor_name: "market_ticks_detected"
               },
               schema_policy: %{config: :defined, signal: :defined},
               jido: %{sensor: %{name: "market_tick_sensor"}},
               secret_requirements: [],
               metadata: %{}
             })

    @impl true
    def manifest do
      %Manifest{
        connector: "projected_trigger_signal_metadata",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :api_token,
            install: %{required: false},
            reauth: %{supported: false},
            requested_scopes: ["market:read"],
            lease_fields: ["access_token"],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "Projected Trigger Signal Metadata Drift",
            description: "Connector with a manually drifted projected trigger",
            category: "test",
            tags: ["projection"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [],
        triggers: [@trigger],
        runtime_families: [:direct],
        capabilities: [Capability.from_trigger!("projected_trigger_signal_metadata", @trigger)],
        metadata: %{}
      }
    end

    def ingress_definitions do
      [
        %{
          source: :poll,
          connector_id: "projected_trigger_signal_metadata",
          trigger_id: "market.ticks.detected",
          capability_id: "projected_trigger_signal_metadata.market.tick.detected",
          signal_type: "market.tick.detected",
          signal_source: "/ingress/poll/projected_trigger_signal_metadata/market.ticks.detected",
          validator: nil,
          dedupe_ttl_seconds: 300
        }
      ]
    end
  end

  defmodule ProjectedTriggerJidoSensorNameDriftConnector do
    @behaviour Connector

    @trigger struct!(TriggerSpec, %{
               trigger_id: "projected_trigger_jido_sensor_name.market.tick.detected",
               name: "market_tick_detected",
               display_name: "Market tick detected",
               description: "Projected trigger missing the generated Jido sensor name",
               runtime_class: :direct,
               delivery_mode: :poll,
               handler: TriggerHandler,
               config_schema:
                 Zoi.object(%{
                   interval_ms: Zoi.integer() |> Zoi.default(60_000)
                 }),
               signal_schema:
                 Zoi.object(%{
                   symbol: Zoi.string(),
                   price: Zoi.number()
                 }),
               permissions: %{required_scopes: ["market:read"]},
               checkpoint: %{strategy: :cursor},
               dedupe: %{strategy: :event_id},
               verification: %{},
               policy: %{},
               consumer_surface: %{
                 mode: :common,
                 normalized_id: "market.ticks.detected",
                 sensor_name: "market_ticks_detected"
               },
               schema_policy: %{config: :defined, signal: :defined},
               jido: %{
                 sensor: %{
                   signal_type: "market.tick.detected",
                   signal_source:
                     "/ingress/poll/projected_trigger_jido_sensor_name/market.ticks.detected"
                 }
               },
               secret_requirements: [],
               metadata: %{}
             })

    @impl true
    def manifest do
      %Manifest{
        connector: "projected_trigger_jido_sensor_name",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :api_token,
            install: %{required: false},
            reauth: %{supported: false},
            requested_scopes: ["market:read"],
            lease_fields: ["access_token"],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "Projected Trigger Jido Sensor Name Drift",
            description: "Connector with a manually drifted projected trigger Jido sensor name",
            category: "test",
            tags: ["projection"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [],
        triggers: [@trigger],
        runtime_families: [:direct],
        capabilities: [Capability.from_trigger!("projected_trigger_jido_sensor_name", @trigger)],
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
             :consumer_surface_projection,
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

  test "accepts target-driver-backed non-direct marker handlers in runtime fit" do
    runtime_suite = RuntimeClassFit.run(%{manifest: HarnessBackedStreamConnector.manifest()})

    assert runtime_suite.status == :passed
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

  test "fails conformance when ingress evidence drifts from trigger identity and signal metadata" do
    assert {:ok, report} =
             Conformance.run(
               TriggerIdentityDriftConnector,
               profile: :connector_foundation,
               generated_at: ~U[2026-03-12 00:00:00Z]
             )

    ingress_suite = Enum.find(report.suite_results, &(&1.id == :ingress_definition_discipline))

    assert ingress_suite.status == :failed
    assert failed_check?(ingress_suite.checks, "ingress.trigger.event.ingest.trigger_id")
    assert failed_check?(ingress_suite.checks, "ingress.trigger.event.ingest.signal_type")
    assert failed_check?(ingress_suite.checks, "ingress.trigger.event.ingest.signal_source")
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

  test "fails conformance when a projected common surface uses passthrough schemas" do
    assert {:ok, report} =
             Conformance.run(
               ProjectedPlaceholderConnector,
               profile: :connector_foundation,
               generated_at: ~U[2026-03-12 00:00:00Z]
             )

    projection_suite = Enum.find(report.suite_results, &(&1.id == :consumer_surface_projection))

    assert projection_suite.status == :failed

    assert failed_check?(
             projection_suite.checks,
             "projected_placeholder.issue.fetch.common_surface.schemas_defined"
           )
  end

  test "allows connector-local passthrough schemas when the exemption is explicit" do
    assert {:ok, report} =
             Conformance.run(
               DeferredPassthroughConnector,
               profile: :connector_foundation,
               generated_at: ~U[2026-03-12 00:00:00Z]
             )

    projection_suite = Enum.find(report.suite_results, &(&1.id == :consumer_surface_projection))

    assert projection_suite.status == :passed
  end

  test "fails conformance when a projected common trigger omits signal metadata" do
    assert {:ok, report} =
             Conformance.run(
               ProjectedTriggerSignalMetadataDriftConnector,
               profile: :connector_foundation,
               generated_at: ~U[2026-03-12 00:00:00Z]
             )

    projection_suite = Enum.find(report.suite_results, &(&1.id == :consumer_surface_projection))

    assert projection_suite.status == :failed

    assert failed_check?(
             projection_suite.checks,
             "projected_trigger_signal_metadata.market.tick.detected.common_surface.signal_metadata"
           )
  end

  test "fails conformance when a projected common trigger omits the generated Jido sensor name" do
    assert {:ok, report} =
             Conformance.run(
               ProjectedTriggerJidoSensorNameDriftConnector,
               profile: :connector_foundation,
               generated_at: ~U[2026-03-12 00:00:00Z]
             )

    projection_suite = Enum.find(report.suite_results, &(&1.id == :consumer_surface_projection))

    assert projection_suite.status == :failed

    assert failed_check?(
             projection_suite.checks,
             "projected_trigger_jido_sensor_name.market.tick.detected.common_surface.jido_sensor_name"
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
