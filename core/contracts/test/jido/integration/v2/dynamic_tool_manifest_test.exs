defmodule Jido.Integration.V2.DynamicToolManifestTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.DynamicToolManifest
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec

  defmodule Handler do
    def run(_params, _context), do: {:ok, %{}}
  end

  test "maps declared catalog operations into authorized host tool specs" do
    assert {:ok, resolved} =
             DynamicToolManifest.resolve(
               %{tools: ["linear_graphql", "github.pr.create"]},
               connector_manifests: [
                 manifest("linear", "linear.graphql.execute"),
                 manifest("github", "github.pr.create")
               ],
               allowed_operations: ["linear.graphql.execute", "github.pr.create"],
               allowed_tools: ["linear.api.graphql.execute", "github.api.pr.create"],
               authority_ref: "authority://phase11",
               tenant_ref: "tenant://phase11",
               installation_ref: "installation://phase11"
             )

    assert resolved.operations == ["linear.graphql.execute", "github.pr.create"]
    assert Enum.map(resolved.host_tools, & &1["name"]) == ["linear_graphql", "github_pr_create"]

    assert Enum.map(resolved.host_tools, &get_in(&1, ["metadata", "catalog_ref"])) == [
             "linear:linear.graphql.execute",
             "github:github.pr.create"
           ]

    assert Enum.all?(resolved.host_tools, fn host_tool ->
             metadata = host_tool["metadata"]

             String.starts_with?(metadata["manifest_ref"], "jido://v2/connector_manifest/") and
               metadata["manifest_hash"] =~ ~r/^sha256:[a-f0-9]{64}$/ and
               metadata["manifest_state"] == "active"
           end)

    assert hd(resolved.host_tools)["inputSchema"][:type] == :object
    assert resolved.metadata["authority_ref"] == "authority://phase11"
  end

  test "keeps the legacy linear comment tool name mapped to the plural catalog id" do
    assert {:ok, resolved} =
             DynamicToolManifest.resolve(
               %{tools: ["linear.comment.update"]},
               connector_manifests: [manifest("linear", "linear.comments.update")],
               allowed_operations: ["linear.comments.update"],
               allowed_tools: ["linear.api.comments.update"]
             )

    assert resolved.operations == ["linear.comments.update"]
    assert [%{"name" => "linear_comment_update"}] = resolved.host_tools
  end

  test "projects operation-authored dynamic host tool schemas without lower output schema" do
    input_schema = %{
      type: "object",
      additionalProperties: false,
      required: ["query"],
      properties: %{
        query: %{type: "string"},
        variables: %{type: ["object", "null"], additionalProperties: true}
      }
    }

    assert {:ok, resolved} =
             DynamicToolManifest.resolve(
               %{tools: ["linear.graphql.execute"]},
               connector_manifests: [
                 manifest("linear", "linear.graphql.execute",
                   operation_metadata: %{
                     dynamic_host_tool: %{
                       name: "linear_graphql",
                       description: "Execute a governed Linear GraphQL tool.",
                       input_schema: input_schema,
                       output_schema: nil
                     }
                   }
                 )
               ],
               allowed_operations: ["linear.graphql.execute"],
               allowed_tools: ["linear.api.graphql.execute"]
             )

    assert [
             %{
               "name" => "linear_graphql",
               "description" => "Execute a governed Linear GraphQL tool.",
               "inputSchema" => host_input_schema
             } = host_tool
           ] = resolved.host_tools

    assert host_input_schema == %{
             "type" => "object",
             "additionalProperties" => false,
             "required" => ["query"],
             "properties" => %{
               "query" => %{"type" => "string"},
               "variables" => %{"type" => ["object", "null"], "additionalProperties" => true}
             }
           }

    refute Map.has_key?(host_tool, "outputSchema")
  end

  test "rejects tools outside Citadel allowed operations" do
    assert {:error, error} =
             DynamicToolManifest.resolve(
               %{tools: ["github.pr.create"]},
               connector_manifests: [manifest("github", "github.pr.create")],
               allowed_operations: ["linear.graphql.execute"],
               allowed_tools: ["github.api.pr.create"]
             )

    assert String.contains?(Exception.message(error), "not present in Citadel allowed_operations")
  end

  test "rejects multi-operation tool declarations" do
    assert {:error, error} =
             DynamicToolManifest.resolve(
               %{
                 tools: [
                   %{name: "combo", operations: ["linear.graphql.execute", "github.pr.create"]}
                 ]
               },
               connector_manifests: [
                 manifest("linear", "linear.graphql.execute"),
                 manifest("github", "github.pr.create")
               ],
               allowed_operations: ["linear.graphql.execute", "github.pr.create"],
               allowed_tools: ["linear.api.graphql.execute", "github.api.pr.create"]
             )

    assert String.contains?(Exception.message(error), "maps to multiple operations")
  end

  test "rejects undeclared catalog operations" do
    assert {:error, error} =
             DynamicToolManifest.resolve(
               %{tools: ["linear.graphql.execute"]},
               connector_manifests: [manifest("github", "github.pr.create")],
               allowed_operations: ["linear.graphql.execute"],
               allowed_tools: ["linear.api.graphql.execute"]
             )

    assert String.contains?(Exception.message(error), "not present in connector catalogs")
  end

  test "rejects non-idempotent host tools from inactive connector manifests" do
    for manifest_state <- [:stale, :quarantined] do
      assert {:error, error} =
               DynamicToolManifest.resolve(
                 %{tools: ["linear.comment.update"]},
                 connector_manifests: [
                   manifest("linear", "linear.comments.update", manifest_state: manifest_state)
                 ],
                 allowed_operations: ["linear.comments.update"],
                 allowed_tools: ["linear.api.comments.update"]
               )

      assert String.contains?(
               Exception.message(error),
               "non-idempotent dynamic host tool"
             )

      assert String.contains?(Exception.message(error), Atom.to_string(manifest_state))
    end
  end

  test "allows idempotent read host tools from stale manifests for degraded readback" do
    assert {:ok, resolved} =
             DynamicToolManifest.resolve(
               %{tools: ["linear.issues.retrieve"]},
               connector_manifests: [
                 manifest("linear", "linear.issues.retrieve", manifest_state: :stale)
               ],
               allowed_operations: ["linear.issues.retrieve"],
               allowed_tools: ["linear.api.issues.retrieve"]
             )

    assert resolved.operations == ["linear.issues.retrieve"]
    assert get_in(hd(resolved.host_tools), ["metadata", "manifest_state"]) == "stale"
    assert get_in(hd(resolved.host_tools), ["metadata", "side_effect_class"]) == "read"
    assert get_in(hd(resolved.host_tools), ["metadata", "idempotency_class"]) == "idempotent"
  end

  defp manifest(connector, operation_id, opts \\ []) do
    Manifest.new!(%{
      connector: connector,
      auth:
        AuthSpec.new!(%{
          binding_kind: :connection_id,
          auth_type: :oauth2,
          install: %{required: true},
          reauth: %{supported: true},
          requested_scopes: ["write"],
          lease_fields: ["access_token"],
          secret_names: []
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: connector,
          description: "#{connector} connector",
          category: "developer_tools",
          tags: [connector],
          docs_refs: [],
          maturity: :beta,
          publication: :public
        }),
      operations: [operation(operation_id, Keyword.get(opts, :operation_metadata, %{}))],
      triggers: [],
      runtime_families: [:direct],
      metadata: %{manifest_state: Keyword.get(opts, :manifest_state, :active)}
    })
  end

  defp operation(operation_id, metadata) do
    OperationSpec.new!(%{
      operation_id: operation_id,
      name: String.replace(operation_id, ".", "_"),
      display_name: operation_id,
      description: "Executes #{operation_id}",
      runtime_class: :direct,
      transport_mode: :sdk,
      handler: Handler,
      input_schema: Zoi.object(%{input: Zoi.string()}),
      output_schema: Zoi.object(%{ok: Zoi.boolean()}),
      permissions: %{required_scopes: ["write"]},
      policy: %{
        environment: %{allowed: [:prod]},
        sandbox: %{
          level: :standard,
          egress: :restricted,
          approvals: :auto,
          allowed_tools: [
            String.replace(operation_id, "github.", "github.api.")
            |> String.replace("linear.", "linear.api.")
          ]
        }
      },
      upstream: %{method: "POST", path: "/"},
      consumer_surface: %{mode: :connector_local, reason: "test"},
      schema_policy: %{input: :defined, output: :defined},
      jido: %{},
      metadata: metadata
    })
  end
end
