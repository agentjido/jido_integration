defmodule Jido.Integration.V2.ManifestCatalogContractTest do
  use ExUnit.Case

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.TriggerSpec

  defmodule Handler do
    def run(_input, _context), do: {:ok, %{}}
  end

  test "rich authored manifests derive deterministic executable capabilities" do
    manifest =
      Manifest.new!(%{
        connector: "acme",
        auth: %{
          binding_kind: :connection_id,
          auth_type: :oauth2,
          install: %{required: true},
          reauth: %{supported: true},
          requested_scopes: ["issues:read", "issues:write"],
          lease_fields: ["access_token"],
          secret_names: ["webhook_secret"]
        },
        catalog: %{
          display_name: "Acme",
          description: "Acme issue workflows",
          category: "project_management",
          tags: ["issues", "tickets"],
          docs_refs: ["https://docs.example.test/acme"],
          maturity: :beta,
          publication: :public
        },
        operations: [
          %{
            operation_id: "acme.issue.fetch",
            name: "issue_fetch",
            display_name: "Fetch issue",
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
                allowed_tools: ["acme.issue.fetch"]
              }
            },
            upstream: %{method: "GET", path: "/issues/{issue_id}"},
            jido: %{action: %{name: "acme_issue_fetch"}},
            metadata: %{rollout_phase: :a0}
          }
        ],
        triggers: [
          %{
            trigger_id: "acme.issue.updated",
            name: "issue_updated",
            display_name: "Issue updated",
            description: "Accepts webhook issue updates",
            runtime_class: :direct,
            delivery_mode: :webhook,
            handler: Handler,
            config_schema:
              Zoi.object(%{
                webhook_secret: Zoi.string()
              }),
            signal_schema:
              Zoi.object(%{
                issue_id: Zoi.string()
              }),
            permissions: %{required_scopes: ["issues:read"]},
            checkpoint: %{strategy: :cursor},
            dedupe: %{strategy: :event_id},
            verification: %{secret_name: "webhook_secret"},
            jido: %{sensor: %{name: "acme_issue_updated"}},
            metadata: %{published?: false}
          }
        ],
        runtime_families: [:direct],
        metadata: %{provider_sdk: :acme_sdk}
      })

    assert %AuthSpec{} = manifest.auth
    assert %CatalogSpec{} = manifest.catalog
    assert [%OperationSpec{} = operation] = manifest.operations
    assert [%TriggerSpec{} = trigger] = manifest.triggers
    assert manifest.runtime_families == [:direct]
    assert manifest.metadata.provider_sdk == :acme_sdk

    assert [%Capability{} = fetch_capability, %Capability{} = trigger_capability] =
             manifest.capabilities

    assert fetch_capability.id == operation.operation_id
    assert fetch_capability.kind == :operation
    assert fetch_capability.transport_profile == :sdk
    assert fetch_capability.metadata.required_scopes == ["issues:read"]
    assert fetch_capability.metadata.input_schema == operation.input_schema
    assert fetch_capability.metadata.output_schema == operation.output_schema
    assert fetch_capability.metadata.jido.action.name == "acme_issue_fetch"

    assert trigger_capability.id == trigger.trigger_id
    assert trigger_capability.kind == :trigger
    assert trigger_capability.transport_profile == :webhook
    assert trigger_capability.metadata.config_schema == trigger.config_schema
    assert trigger_capability.metadata.signal_schema == trigger.signal_schema
    assert trigger_capability.metadata.verification.secret_name == "webhook_secret"

    assert Enum.map(manifest.capabilities, & &1.id) == ["acme.issue.fetch", "acme.issue.updated"]
    assert Manifest.capabilities(manifest) == manifest.capabilities
  end

  test "manifest rejects manual capability authoring as an authored source of truth" do
    assert_raise ArgumentError, ~r/manual capability authoring/, fn ->
      Manifest.new!(%{
        connector: "legacy",
        capabilities: [
          Capability.new!(%{
            id: "legacy.echo",
            connector: "legacy",
            runtime_class: :direct,
            kind: :operation,
            transport_profile: :action,
            handler: Handler
          })
        ]
      })
    end
  end

  test "manifest requires auth requested scopes to cover authored operation and trigger scopes" do
    assert_raise ArgumentError,
                 ~r/auth.requested_scopes must cover all authored required_scopes/,
                 fn ->
                   Manifest.new!(%{
                     connector: "scope_drift",
                     auth: %{
                       binding_kind: :connection_id,
                       auth_type: :oauth2,
                       install: %{required: true},
                       reauth: %{supported: true},
                       requested_scopes: ["issues:read"],
                       lease_fields: ["access_token"],
                       secret_names: ["webhook_secret"]
                     },
                     catalog: %{
                       display_name: "Scope Drift",
                       description: "Connector with scope drift",
                       category: "test",
                       tags: ["scope"],
                       docs_refs: [],
                       maturity: :experimental,
                       publication: :internal
                     },
                     operations: [
                       %{
                         operation_id: "scope_drift.issue.write",
                         name: "issue_write",
                         runtime_class: :direct,
                         transport_mode: :sdk,
                         handler: Handler,
                         input_schema: Zoi.map(),
                         output_schema: Zoi.map(),
                         permissions: %{required_scopes: ["issues:write"]},
                         policy: %{
                           environment: %{allowed: [:prod]},
                           sandbox: %{
                             level: :standard,
                             egress: :restricted,
                             approvals: :auto,
                             allowed_tools: ["scope_drift.issue.write"]
                           }
                         },
                         upstream: %{method: "POST", path: "/issues"},
                         jido: %{}
                       }
                     ],
                     triggers: [
                       %{
                         trigger_id: "scope_drift.issue.updated",
                         name: "issue_updated",
                         runtime_class: :direct,
                         delivery_mode: :webhook,
                         handler: Handler,
                         config_schema: Zoi.map(),
                         signal_schema: Zoi.map(),
                         permissions: %{required_scopes: ["issues:admin"]},
                         checkpoint: %{strategy: :cursor},
                         dedupe: %{strategy: :event_id},
                         verification: %{secret_name: "webhook_secret"},
                         jido: %{}
                       }
                     ],
                     runtime_families: [:direct]
                   })
                 end
  end

  test "manifest requires auth secret names to cover authored trigger verification and secret requirements" do
    assert_raise ArgumentError,
                 ~r/auth.secret_names must declare all authored trigger secrets/,
                 fn ->
                   Manifest.new!(%{
                     connector: "secret_drift",
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
                       display_name: "Secret Drift",
                       description: "Connector with trigger secret drift",
                       category: "test",
                       tags: ["secret"],
                       docs_refs: [],
                       maturity: :experimental,
                       publication: :internal
                     },
                     operations: [],
                     triggers: [
                       %{
                         trigger_id: "secret_drift.issue.updated",
                         name: "issue_updated",
                         runtime_class: :direct,
                         delivery_mode: :webhook,
                         handler: Handler,
                         config_schema: Zoi.map(),
                         signal_schema: Zoi.map(),
                         permissions: %{required_scopes: ["issues:read"]},
                         checkpoint: %{strategy: :cursor},
                         dedupe: %{strategy: :event_id},
                         verification: %{secret_name: "webhook_secret"},
                         secret_requirements: ["signing_secret"],
                         jido: %{}
                       }
                     ],
                     runtime_families: [:direct]
                   })
                 end
  end

  test "operation and trigger specs require Zoi schemas" do
    assert_raise ArgumentError, ~r/input_schema must be a Zoi schema/, fn ->
      OperationSpec.new!(%{
        operation_id: "acme.issue.fetch",
        name: "issue_fetch",
        runtime_class: :direct,
        transport_mode: :sdk,
        handler: Handler,
        input_schema: %{type: "object"},
        output_schema: Zoi.map(),
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
        jido: %{}
      })
    end

    assert_raise ArgumentError, ~r/config_schema must be a Zoi schema/, fn ->
      TriggerSpec.new!(%{
        trigger_id: "acme.issue.updated",
        name: "issue_updated",
        runtime_class: :direct,
        delivery_mode: :webhook,
        handler: Handler,
        config_schema: %{type: "object"},
        signal_schema: Zoi.map(),
        permissions: %{required_scopes: ["issues:read"]},
        checkpoint: %{strategy: :cursor},
        dedupe: %{strategy: :event_id},
        verification: %{secret_name: "webhook_secret"},
        jido: %{}
      })
    end
  end
end
