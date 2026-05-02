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

  test "rejects tools outside Citadel allowed operations" do
    assert {:error, error} =
             DynamicToolManifest.resolve(
               %{tools: ["github.pr.create"]},
               connector_manifests: [manifest("github", "github.pr.create")],
               allowed_operations: ["linear.graphql.execute"],
               allowed_tools: ["github.api.pr.create"]
             )

    assert Exception.message(error) =~ "not present in Citadel allowed_operations"
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

    assert Exception.message(error) =~ "maps to multiple operations"
  end

  test "rejects undeclared catalog operations" do
    assert {:error, error} =
             DynamicToolManifest.resolve(
               %{tools: ["linear.graphql.execute"]},
               connector_manifests: [manifest("github", "github.pr.create")],
               allowed_operations: ["linear.graphql.execute"],
               allowed_tools: ["linear.api.graphql.execute"]
             )

    assert Exception.message(error) =~ "not present in connector catalogs"
  end

  defp manifest(connector, operation_id) do
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
      operations: [operation(operation_id)],
      triggers: [],
      runtime_families: [:direct]
    })
  end

  defp operation(operation_id) do
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
      jido: %{}
    })
  end
end
