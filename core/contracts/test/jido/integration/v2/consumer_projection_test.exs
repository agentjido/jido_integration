defmodule Jido.Integration.V2.ConsumerProjectionTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.ConsumerProjection
  alias Jido.Integration.V2.InvocationRequest
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec

  defmodule Handler do
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule AcmeConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "acme",
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
            display_name: "Acme",
            description: "Acme issue workflows",
            category: "developer_tools",
            tags: ["issues"],
            docs_refs: ["https://docs.example.test/acme"],
            maturity: :beta,
            publication: :public
          }),
        operations: [
          OperationSpec.new!(%{
            operation_id: "acme.issue.fetch",
            name: "issue_fetch",
            display_name: "Issue fetch",
            description: "Fetches one Acme issue",
            runtime_class: :direct,
            transport_mode: :sdk,
            handler: Handler,
            input_schema:
              Zoi.object(%{
                issue_id: Zoi.string()
              }),
            output_schema:
              Zoi.object(%{
                id: Zoi.string()
              }),
            permissions: %{required_scopes: ["issues:read"]},
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: ["acme.issue.fetch"]
              }
            },
            upstream: %{method: "GET", path: "/issues/{issue_id}"},
            consumer_surface: %{
              mode: :common,
              normalized_id: "work_item.fetch",
              action_name: "work_item_fetch"
            },
            schema_policy: %{input: :defined, output: :defined},
            jido: %{action: %{name: "acme_issue_fetch"}}
          })
        ],
        triggers: [],
        runtime_families: [:direct]
      })
    end
  end

  defmodule DuplicateProjectedSurfaceConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "duplicate",
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
            display_name: "Duplicate",
            description: "Connector with colliding generated action surfaces",
            category: "developer_tools",
            tags: ["issues"],
            docs_refs: ["https://docs.example.test/duplicate"],
            maturity: :beta,
            publication: :private
          }),
        operations: [
          OperationSpec.new!(%{
            operation_id: "duplicate.issue.fetch",
            name: "issue_fetch",
            display_name: "Issue fetch",
            description: "Fetches one issue",
            runtime_class: :direct,
            transport_mode: :sdk,
            handler: Handler,
            input_schema:
              Zoi.object(%{
                issue_id: Zoi.string()
              }),
            output_schema:
              Zoi.object(%{
                id: Zoi.string()
              }),
            permissions: %{required_scopes: ["issues:read"]},
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: ["duplicate.issue.fetch"]
              }
            },
            upstream: %{method: "GET", path: "/issues/{issue_id}"},
            consumer_surface: %{
              mode: :common,
              normalized_id: "work_item.fetch",
              action_name: "work_item_fetch"
            },
            schema_policy: %{input: :defined, output: :defined},
            jido: %{action: %{name: "duplicate_issue"}}
          }),
          OperationSpec.new!(%{
            operation_id: "duplicate.issue.lookup",
            name: "issue_fetch",
            display_name: "Issue lookup",
            description: "Looks up one issue",
            runtime_class: :direct,
            transport_mode: :sdk,
            handler: Handler,
            input_schema:
              Zoi.object(%{
                issue_id: Zoi.string()
              }),
            output_schema:
              Zoi.object(%{
                id: Zoi.string()
              }),
            permissions: %{required_scopes: ["issues:read"]},
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: ["duplicate.issue.lookup"]
              }
            },
            upstream: %{method: "GET", path: "/issues/{issue_id}"},
            consumer_surface: %{
              mode: :common,
              normalized_id: "work_item.fetch",
              action_name: "work_item_fetch"
            },
            schema_policy: %{input: :defined, output: :defined},
            jido: %{action: %{name: "duplicate_issue"}}
          })
        ],
        triggers: [],
        runtime_families: [:direct]
      })
    end
  end

  defmodule MixedSurfaceConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "mixed",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :oauth2,
            install: %{required: true},
            reauth: %{supported: true},
            requested_scopes: ["issues:read", "provider:raw"],
            lease_fields: ["access_token"],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "Mixed",
            description: "Connector with projected and connector-local runtime operations",
            category: "developer_tools",
            tags: ["issues", "mixed"],
            docs_refs: ["https://docs.example.test/mixed"],
            maturity: :beta,
            publication: :public
          }),
        operations: [
          OperationSpec.new!(%{
            operation_id: "mixed.issue.fetch",
            name: "issue_fetch",
            display_name: "Issue fetch",
            description: "Fetches one issue through a normalized common surface",
            runtime_class: :direct,
            transport_mode: :sdk,
            handler: Handler,
            input_schema:
              Zoi.object(%{
                issue_id: Zoi.string()
              }),
            output_schema:
              Zoi.object(%{
                id: Zoi.string()
              }),
            permissions: %{required_scopes: ["issues:read"]},
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: ["mixed.issue.fetch"]
              }
            },
            upstream: %{method: "GET", path: "/issues/{issue_id}"},
            consumer_surface: %{
              mode: :common,
              normalized_id: "work_item.fetch",
              action_name: "work_item_fetch"
            },
            schema_policy: %{input: :defined, output: :defined},
            jido: %{}
          }),
          OperationSpec.new!(%{
            operation_id: "mixed.provider.raw_lookup",
            name: "provider_raw_lookup",
            display_name: "Provider raw lookup",
            description: "Keeps a provider-specific long-tail method out of projected surfaces",
            runtime_class: :direct,
            transport_mode: :sdk,
            handler: Handler,
            input_schema: Zoi.map(),
            output_schema: Zoi.map(),
            permissions: %{required_scopes: ["provider:raw"]},
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: ["mixed.provider.raw_lookup"]
              }
            },
            upstream: %{method: "GET", path: "/provider/raw_lookup"},
            consumer_surface: %{
              mode: :connector_local,
              reason: "Provider-specific long-tail behavior stays at the SDK boundary"
            },
            schema_policy: %{
              input: :passthrough,
              output: :passthrough,
              justification:
                "Connector-local runtime passthrough while the operation remains outside the common projected surface"
            },
            jido: %{}
          })
        ],
        triggers: [],
        runtime_families: [:direct]
      })
    end
  end

  defmodule CrossRuntimeProjectedConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "cross_runtime",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :oauth2,
            install: %{required: true},
            reauth: %{supported: true},
            requested_scopes: ["ops:execute", "provider:raw"],
            lease_fields: ["access_token"],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "Cross Runtime",
            description: "Connector with direct, session, and stream common surfaces",
            category: "developer_tools",
            tags: ["cross-runtime"],
            docs_refs: ["https://docs.example.test/cross-runtime"],
            maturity: :beta,
            publication: :internal
          }),
        operations: [
          OperationSpec.new!(%{
            operation_id: "cross_runtime.issue.fetch",
            name: "issue_fetch",
            display_name: "Issue fetch",
            description: "Fetches one issue directly",
            runtime_class: :direct,
            transport_mode: :sdk,
            handler: Handler,
            input_schema:
              Zoi.object(%{
                issue_id: Zoi.string()
              }),
            output_schema:
              Zoi.object(%{
                id: Zoi.string()
              }),
            permissions: %{required_scopes: ["ops:execute"]},
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: ["cross_runtime.issue.fetch"]
              }
            },
            upstream: %{method: "GET", path: "/issues/{issue_id}"},
            consumer_surface: %{
              mode: :common,
              normalized_id: "work_item.fetch",
              action_name: "work_item_fetch"
            },
            schema_policy: %{input: :defined, output: :defined},
            jido: %{}
          }),
          OperationSpec.new!(%{
            operation_id: "cross_runtime.session.exec",
            name: "session_exec",
            display_name: "Session exec",
            description: "Routes through a reusable session runtime",
            runtime_class: :session,
            transport_mode: :stdio,
            handler: Handler,
            input_schema:
              Zoi.object(%{
                prompt: Zoi.string()
              }),
            output_schema:
              Zoi.object(%{
                text: Zoi.string()
              }),
            permissions: %{required_scopes: ["ops:execute"]},
            runtime: %{
              driver: "asm",
              provider: :codex,
              options: %{}
            },
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :manual,
                allowed_tools: ["cross_runtime.session.exec"]
              }
            },
            upstream: %{transport: :stdio},
            consumer_surface: %{
              mode: :common,
              normalized_id: "codex.session.turn",
              action_name: "codex_session_turn"
            },
            schema_policy: %{input: :defined, output: :defined},
            jido: %{},
            metadata: %{
              runtime_family: %{
                session_affinity: :connection,
                resumable: true,
                approval_required: true,
                stream_capable: true,
                lifecycle_owner: :asm,
                runtime_ref: :session
              }
            }
          }),
          OperationSpec.new!(%{
            operation_id: "cross_runtime.stream.pull",
            name: "stream_pull",
            display_name: "Stream pull",
            description: "Routes through a stream-capable runtime",
            runtime_class: :stream,
            transport_mode: :stdio,
            handler: Handler,
            input_schema:
              Zoi.object(%{
                query: Zoi.string()
              }),
            output_schema:
              Zoi.object(%{
                rows: Zoi.list(Zoi.map())
              }),
            permissions: %{required_scopes: ["ops:execute"]},
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
                allowed_tools: ["cross_runtime.stream.pull"]
              }
            },
            upstream: %{transport: :stdio},
            consumer_surface: %{
              mode: :common,
              normalized_id: "market.ticks.pull",
              action_name: "market_ticks_pull"
            },
            schema_policy: %{input: :defined, output: :defined},
            jido: %{},
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
          }),
          OperationSpec.new!(%{
            operation_id: "cross_runtime.provider.raw_lookup",
            name: "provider_raw_lookup",
            display_name: "Provider raw lookup",
            description: "Stays off the common projection spine",
            runtime_class: :session,
            transport_mode: :stdio,
            handler: Handler,
            input_schema: Zoi.map(),
            output_schema: Zoi.map(),
            permissions: %{required_scopes: ["provider:raw"]},
            runtime: %{driver: "asm"},
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :manual,
                allowed_tools: ["cross_runtime.provider.raw_lookup"]
              }
            },
            upstream: %{transport: :stdio},
            consumer_surface: %{
              mode: :connector_local,
              reason: "Provider-specific runtime behavior stays connector-local"
            },
            schema_policy: %{
              input: :passthrough,
              output: :passthrough,
              justification:
                "Connector-local runtime passthrough while the operation stays outside the common projected surface"
            },
            jido: %{},
            metadata: %{}
          })
        ],
        triggers: [],
        runtime_families: [:direct, :session, :stream]
      })
    end
  end

  test "derives deterministic action projection rules from the authored manifest" do
    projection = ConsumerProjection.action_projection!(AcmeConnector, "acme.issue.fetch")
    [operation] = AcmeConnector.manifest().operations

    assert projection.module == AcmeConnector.Generated.Actions.WorkItemFetch
    assert projection.plugin_module == AcmeConnector.Generated.Plugin
    assert projection.operation_id == "acme.issue.fetch"
    assert projection.normalized_id == "work_item.fetch"
    assert projection.action_name == "work_item_fetch"
    assert projection.description == operation.description
    assert projection.category == "developer_tools"
    assert projection.tags == ["issues", "acme", "direct"]
    assert projection.schema == operation.input_schema
    assert projection.output_schema == operation.output_schema

    assert ConsumerProjection.action_opts(projection)[:schema] == operation.input_schema
    assert ConsumerProjection.action_opts(projection)[:output_schema] == operation.output_schema
  end

  test "derives deterministic plugin projection rules and config schema" do
    projection = ConsumerProjection.plugin_projection!(AcmeConnector)

    assert projection.module == AcmeConnector.Generated.Plugin
    assert projection.name == "acme"
    assert projection.state_key == :acme
    assert projection.description == "Generated plugin bundle for Acme"
    assert projection.category == "developer_tools"
    assert projection.tags == ["issues", "acme", "generated"]
    assert projection.actions == [AcmeConnector.Generated.Actions.WorkItemFetch]

    assert {:ok, parsed_config} =
             Zoi.parse(
               projection.config_schema,
               %{connection_id: "conn-acme-1", enabled_actions: ["work_item_fetch"]}
             )

    assert parsed_config.connection_id == "conn-acme-1"
    assert parsed_config.enabled_actions == ["work_item_fetch"]
  end

  test "builds typed invocation requests from params and plugin runtime context" do
    projection = ConsumerProjection.action_projection!(AcmeConnector, "acme.issue.fetch")

    assert %InvocationRequest{
             capability_id: "acme.issue.fetch",
             connection_id: "conn-acme-param",
             input: %{issue_id: "issue-123"},
             trace_id: "trace-acme-1"
           } =
             ConsumerProjection.invocation_request!(
               projection,
               %{issue_id: "issue-123", connection_id: "conn-acme-param"},
               %{trace_id: "trace-acme-1"}
             )

    assert %InvocationRequest{
             capability_id: "acme.issue.fetch",
             connection_id: "conn-acme-plugin",
             input: %{issue_id: "issue-456"}
           } =
             ConsumerProjection.invocation_request!(
               projection,
               %{issue_id: "issue-456"},
               %{plugin_config: %{connection_id: "conn-acme-plugin"}}
             )
  end

  test "rejects manifests that collide on generated action modules or action names" do
    assert_raise ArgumentError,
                 ~r/generated consumer action projections must be unique within a connector/,
                 fn ->
                   ConsumerProjection.plugin_projection!(DuplicateProjectedSurfaceConnector)
                 end
  end

  test "projects only explicitly common consumer surfaces" do
    projection = ConsumerProjection.plugin_projection!(MixedSurfaceConnector)

    assert projection.actions == [MixedSurfaceConnector.Generated.Actions.WorkItemFetch]
    assert ConsumerProjection.action_modules(MixedSurfaceConnector) == projection.actions

    assert_raise ArgumentError, ~r/not projected into the common consumer surface/, fn ->
      ConsumerProjection.action_projection!(MixedSurfaceConnector, "mixed.provider.raw_lookup")
    end
  end

  test "keeps direct session and stream common surfaces on the one consumer projection spine" do
    projection = ConsumerProjection.plugin_projection!(CrossRuntimeProjectedConnector)

    assert projection.actions == [
             CrossRuntimeProjectedConnector.Generated.Actions.WorkItemFetch,
             CrossRuntimeProjectedConnector.Generated.Actions.CodexSessionTurn,
             CrossRuntimeProjectedConnector.Generated.Actions.MarketTicksPull
           ]

    assert ConsumerProjection.action_modules(CrossRuntimeProjectedConnector) == projection.actions

    assert ConsumerProjection.action_projection!(
             CrossRuntimeProjectedConnector,
             "cross_runtime.issue.fetch"
           ).tags == ["cross-runtime", "cross_runtime", "direct"]

    assert ConsumerProjection.action_projection!(
             CrossRuntimeProjectedConnector,
             "cross_runtime.session.exec"
           ).tags == ["cross-runtime", "cross_runtime", "session"]

    assert ConsumerProjection.action_projection!(
             CrossRuntimeProjectedConnector,
             "cross_runtime.stream.pull"
           ).tags == ["cross-runtime", "cross_runtime", "stream"]
  end

  test "projection structs expose canonical Zoi schema helpers" do
    action_projection_attrs = %{
      connector_module: AcmeConnector,
      plugin_module: AcmeConnector.Generated.Plugin,
      module: AcmeConnector.Generated.Actions.WorkItemFetch,
      operation_id: "acme.issue.fetch",
      normalized_id: "work_item.fetch",
      action_name: "work_item_fetch",
      description: "Fetches one Acme issue",
      category: "developer_tools",
      tags: ["issues", "acme", "direct"],
      schema:
        Zoi.object(%{
          issue_id: Zoi.string()
        }),
      output_schema:
        Zoi.object(%{
          id: Zoi.string()
        })
    }

    plugin_projection_attrs = %{
      connector_module: AcmeConnector,
      module: AcmeConnector.Generated.Plugin,
      name: "acme",
      state_key: :acme,
      description: "Generated plugin bundle for Acme",
      category: "developer_tools",
      tags: ["issues", "acme", "generated"],
      config_schema:
        Zoi.object(%{
          connection_id: Zoi.string(),
          enabled_actions: Zoi.list(Zoi.string()) |> Zoi.default([])
        }),
      actions: [AcmeConnector.Generated.Actions.WorkItemFetch]
    }

    for {module, attrs} <- [
          {ConsumerProjection.ActionProjection, action_projection_attrs},
          {ConsumerProjection.PluginProjection, plugin_projection_attrs}
        ] do
      assert Code.ensure_loaded?(module)
      assert function_exported?(module, :schema, 0)
      assert function_exported?(module, :new, 1)
      assert function_exported?(module, :new!, 1)
      assert %Zoi.Types.Struct{module: ^module} = module.schema()
      assert {:ok, struct} = module.new(attrs)
      assert module == struct.__struct__
      assert ^struct = module.new!(attrs)
    end
  end
end
