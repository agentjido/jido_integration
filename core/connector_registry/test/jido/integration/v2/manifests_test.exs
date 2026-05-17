defmodule Jido.Integration.V2.ManifestsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Connectors.CodexCli
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.Linear
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.ManifestRegistry
  alias Jido.Integration.V2.Manifests
  alias Jido.Integration.V2.OperationLookupRequest
  alias Jido.Integration.V2.OperationSpec

  defmodule Handler do
    def run(_input, _context), do: {:ok, %{}}
  end

  test "resolves a fake manifest operation into a hot-path descriptor" do
    entry = fake_entry()

    assert {:ok, descriptor} =
             entry
             |> request()
             |> Manifests.resolve_operation(manifest_entries: [entry])

    assert descriptor.connector_ref == "connector://example/docs"
    assert descriptor.manifest_ref == "manifest://example/docs/v1"
    assert descriptor.operation_ref == "example.documents.list"
    assert descriptor.operation_role == :source_read
    assert descriptor.operation_class == :source_read
    assert descriptor.binding_kind == :connection_id
    assert descriptor.side_effect_class == :read
    assert descriptor.runtime_family == :direct
    assert descriptor.manifest_digest == entry.manifest_digest
    assert descriptor.required_scopes == ["documents:read"]
    assert descriptor.provider_operation_id == "provider.documents.list"
    assert descriptor.metadata.binding_ref == "binding://tenant/example/docs/source"
  end

  test "fails closed for missing manifest and operation refs" do
    entry = fake_entry()

    assert {:error, {:connector_manifest_missing, "connector://missing/docs"}} =
             Manifests.resolve_operation(
               request(entry, connector_ref: "connector://missing/docs"),
               manifest_entries: [entry]
             )

    assert {:error,
            {:operation_ref_missing, "connector://example/docs", "example.documents.missing"}} =
             Manifests.resolve_operation(
               request(entry, operation_ref: "example.documents.missing"),
               manifest_entries: [entry]
             )
  end

  test "fails closed for manifest digest and binding compatibility drift" do
    entry = fake_entry()

    assert {:error,
            {:manifest_digest_mismatch, "binding://tenant/example/docs/source", "sha256:stale",
             current_digest}} =
             Manifests.resolve_operation(
               request(entry, compiled_manifest_hash: "sha256:stale"),
               manifest_entries: [entry]
             )

    assert current_digest == entry.manifest_digest

    assert {:error,
            {:operation_class_mismatch, "example.documents.list", :runtime_tool_invocation,
             :source_read}} =
             Manifests.resolve_operation(
               request(entry, operation_class: :runtime_tool_invocation),
               manifest_entries: [entry]
             )

    assert {:error,
            {:binding_kind_mismatch, "example.documents.list", :provider_account, :connection_id}} =
             Manifests.resolve_operation(
               request(entry, binding_kind: :provider_account),
               manifest_entries: [entry]
             )

    assert {:error, {:runtime_family_mismatch, "example.documents.list", :session, :direct}} =
             Manifests.resolve_operation(
               request(entry, required_runtime_family: :session),
               manifest_entries: [entry]
             )

    assert {:error,
            {:credential_scope_mismatch, "example.documents.list",
             "credential-scope://tenant/example/other", "credential-scope://tenant/example/docs"}} =
             Manifests.resolve_operation(
               request(entry, credential_scope_ref: "credential-scope://tenant/example/other"),
               manifest_entries: [entry]
             )
  end

  test "verifies compiled descriptors against manifest drift" do
    entry = fake_entry()
    {:ok, descriptor} = Manifests.resolve_operation(request(entry), manifest_entries: [entry])

    assert {:ok, :exact} = Manifests.verify_dependency(descriptor, manifest_entries: [entry])

    compatible_entry =
      fake_entry(manifest: fake_manifest(connector_metadata: %{published_revision: 2}))

    assert {:ok, {:compatible, compatible_descriptor}} =
             Manifests.verify_dependency(descriptor, manifest_entries: [compatible_entry])

    assert compatible_descriptor.manifest_digest == compatible_entry.manifest_digest

    expanded_entry =
      fake_entry(manifest: fake_manifest(required_scopes: ["documents:read", "documents:write"]))

    assert {:error, {:operation_scope_expanded_since_compile, "example.documents.list"}} =
             Manifests.verify_dependency(descriptor, manifest_entries: [expanded_entry])

    effect_entry =
      fake_entry(manifest: fake_manifest(side_effect_class: :write))

    assert {:error, {:side_effect_class_expanded_since_compile, "example.documents.list"}} =
             Manifests.verify_dependency(descriptor, manifest_entries: [effect_entry])
  end

  test "published GitHub Linear and Codex manifests resolve without live credentials" do
    entries = [
      official_entry(
        "connector://github/official-rest",
        "manifest://github/official-rest/current",
        GitHub,
        "http"
      ),
      official_entry(
        "connector://linear/official-graphql",
        "manifest://linear/official-graphql/current",
        Linear,
        "graphql"
      ),
      official_entry(
        "connector://codex-cli/official-session",
        "manifest://codex-cli/official-session/current",
        CodexCli,
        "cli"
      )
    ]

    for entry <- entries do
      operation = hd(entry.manifest.operations)

      assert {:ok, ^entry} =
               Manifests.fetch_connector_manifest(entry.connector_ref, manifest_entries: entries)

      assert {:ok, _manifest, ^operation} =
               Manifests.fetch_operation(entry.connector_ref, operation.operation_id,
                 manifest_entries: entries
               )

      assert {:ok, descriptor} =
               Manifests.resolve_operation(
                 request(entry,
                   operation_ref: operation.operation_id,
                   operation_role: :runtime_tool,
                   operation_class: :connector_operation,
                   binding_kind: entry.manifest.auth.binding_kind,
                   required_runtime_family: operation.runtime_class
                 ),
                 manifest_entries: entries
               )

      assert descriptor.manifest_digest == entry.manifest_digest
      assert descriptor.provider_family == entry.provider_family
      assert descriptor.required_scopes != []
    end
  end

  defp request(entry, overrides \\ []) do
    attrs =
      %{
        connector_ref: entry.connector_ref,
        manifest_ref: entry.manifest_ref,
        operation_ref: "example.documents.list",
        operation_role: :source_read,
        operation_class: :source_read,
        binding_kind: :connection_id,
        required_runtime_family: :direct,
        binding_ref: "binding://tenant/example/docs/source",
        pack_ref: "pack://example/doc-review",
        pack_revision: "1",
        credential_scope_ref: "credential-scope://tenant/example/docs",
        compiled_manifest_hash: entry.manifest_digest,
        trace_ref: "trace://lookup/1",
        metadata: %{}
      }
      |> Map.merge(Map.new(overrides))

    OperationLookupRequest.new!(attrs)
  end

  defp fake_entry(overrides \\ []) do
    attrs =
      %{
        connector_ref: "connector://example/docs",
        manifest_ref: "manifest://example/docs/v1",
        manifest: fake_manifest(),
        provider_family: "http",
        adapter_ref: "adapter://example/docs",
        connector_version: "1.0.0",
        metadata: %{credential_scope_ref: "credential-scope://tenant/example/docs"}
      }
      |> Map.merge(Map.new(overrides))

    ManifestRegistry.Entry.new!(attrs)
  end

  defp fake_manifest(overrides \\ []) do
    required_scopes = Keyword.get(overrides, :required_scopes, ["documents:read"])
    side_effect_class = Keyword.get(overrides, :side_effect_class, :read)
    connector_metadata = Keyword.get(overrides, :connector_metadata, %{})

    Manifest.new!(%{
      connector: "example_docs",
      auth:
        AuthSpec.new!(%{
          binding_kind: :connection_id,
          auth_type: :api_token,
          install: %{required: true},
          reauth: %{supported: false},
          requested_scopes: required_scopes,
          lease_fields: ["access_token"],
          secret_names: []
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: "Example Docs",
          description: "Example document connector",
          category: "documents",
          tags: ["documents"],
          docs_refs: [],
          maturity: :experimental,
          publication: :internal
        }),
      operations: [
        OperationSpec.new!(%{
          operation_id: "example.documents.list",
          name: "documents_list",
          display_name: "List documents",
          description: "Lists documents",
          runtime_class: :direct,
          transport_mode: :http,
          handler: Handler,
          input_schema:
            Zoi.object(%{
              cursor: Zoi.string() |> Zoi.optional()
            }),
          output_schema:
            Zoi.object(%{
              document_ids: Zoi.list(Zoi.string())
            }),
          permissions: %{required_scopes: required_scopes},
          runtime: %{},
          policy: %{},
          upstream: %{method: "GET", path: "/documents"},
          consumer_surface: %{
            mode: :common,
            normalized_id: "documents.list",
            action_name: "documents_list"
          },
          schema_policy: %{input: :defined, output: :defined},
          jido: %{action: %{name: "documents_list"}},
          metadata: %{
            operation_class: :source_read,
            side_effect_class: side_effect_class,
            provider_operation_id: "provider.documents.list",
            input_schema_ref: "schema://example/documents/list/input",
            output_schema_ref: "schema://example/documents/list/output"
          }
        })
      ],
      triggers: [],
      runtime_families: [:direct],
      metadata: Map.merge(%{provider_sdk: :example_docs}, connector_metadata)
    })
  end

  defp official_entry(connector_ref, manifest_ref, module, provider_family) do
    ManifestRegistry.Entry.new!(
      connector_ref: connector_ref,
      manifest_ref: manifest_ref,
      manifest: module,
      provider_family: provider_family,
      connector_version: "1.0.0"
    )
  end
end
