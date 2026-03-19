defmodule Jido.Integration.V2.ConsumerProjectionTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.ConsumerProjection
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
            jido: %{action: %{name: "acme_issue_fetch"}}
          })
        ],
        triggers: [],
        runtime_families: [:direct]
      })
    end
  end

  test "derives deterministic action projection rules from the authored manifest" do
    projection = ConsumerProjection.action_projection!(AcmeConnector, "acme.issue.fetch")
    [operation] = AcmeConnector.manifest().operations

    assert projection.module == AcmeConnector.Generated.Actions.IssueFetch
    assert projection.plugin_module == AcmeConnector.Generated.Plugin
    assert projection.operation_id == "acme.issue.fetch"
    assert projection.action_name == "acme_issue_fetch"
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
    assert projection.actions == [AcmeConnector.Generated.Actions.IssueFetch]

    assert {:ok, parsed_config} =
             Zoi.parse(
               projection.config_schema,
               %{connection_id: "conn-acme-1", enabled_actions: ["acme_issue_fetch"]}
             )

    assert parsed_config.connection_id == "conn-acme-1"
    assert parsed_config.enabled_actions == ["acme_issue_fetch"]
  end
end
