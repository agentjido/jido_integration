defmodule Jido.Integration.V2.OperationLookupContractTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.OperationDescriptor
  alias Jido.Integration.V2.OperationLookupRequest

  test "normalizes operation lookup request fields" do
    assert %OperationLookupRequest{} =
             request =
             OperationLookupRequest.new!(%{
               connector_ref: "connector://example/docs",
               manifest_ref: "manifest://example/docs/v1",
               operation_ref: "example.documents.list",
               operation_role: :source_read,
               operation_class: :source_read,
               binding_kind: :connection_id,
               required_runtime_family: "direct",
               binding_ref: "binding://tenant/example/docs/source",
               pack_ref: "pack://example/doc-review",
               pack_revision: "1",
               credential_scope_ref: "credential-scope://tenant/example/docs",
               compiled_manifest_hash: "sha256:abc",
               trace_ref: "trace://lookup/1",
               metadata: %{"tenant" => "tenant-1"}
             })

    assert request.required_runtime_family == :direct
    assert request.compiled_manifest_hash == "sha256:abc"
    assert request.metadata == %{"tenant" => "tenant-1"}
  end

  test "normalizes operation descriptor fields" do
    assert %OperationDescriptor{} =
             descriptor =
             OperationDescriptor.new!(%{
               operation_manifest_ref:
                 "manifest://example/docs/v1#operation:example.documents.list",
               connector_ref: "connector://example/docs",
               manifest_ref: "manifest://example/docs/v1",
               operation_ref: "example.documents.list",
               operation_role: :source_read,
               operation_class: :source_read,
               binding_kind: :connection_id,
               side_effect_class: :read,
               input_schema_ref: "schema://example/documents/list/input",
               output_schema_ref: "schema://example/documents/list/output",
               credential_scope_ref: "credential-scope://tenant/example/docs",
               runtime_family: "direct",
               manifest_digest: "sha256:abc",
               required_scopes: [:documents_read],
               provider_family: "http",
               provider_operation_id: "provider.documents.list",
               connector_version: "1.0.0",
               adapter_ref: "adapter://example/docs",
               handler_ref: "Example.Handler",
               metadata: %{binding_ref: "binding://tenant/example/docs/source"}
             })

    assert descriptor.runtime_family == :direct
    assert descriptor.required_scopes == ["documents_read"]
    assert descriptor.metadata.binding_ref == "binding://tenant/example/docs/source"
  end

  test "normalizes operation lookup and descriptor vocabularies from strings" do
    request =
      OperationLookupRequest.new!(%{
        connector_ref: "connector://example/docs",
        manifest_ref: "manifest://example/docs/v1",
        operation_ref: "example.documents.list",
        operation_role: "source_read",
        operation_class: "source_read",
        binding_kind: "connection_id",
        required_runtime_family: "direct",
        binding_ref: "binding://tenant/example/docs/source",
        pack_ref: "pack://example/doc-review",
        pack_revision: "1",
        credential_scope_ref: "credential-scope://tenant/example/docs"
      })

    descriptor =
      OperationDescriptor.new!(%{
        operation_manifest_ref: "manifest://example/docs/v1#operation:example.documents.list",
        connector_ref: "connector://example/docs",
        manifest_ref: "manifest://example/docs/v1",
        operation_ref: "example.documents.list",
        operation_role: "source_read",
        operation_class: "source_read",
        binding_kind: "connection_id",
        side_effect_class: "read",
        input_schema_ref: "schema://example/documents/list/input",
        output_schema_ref: "schema://example/documents/list/output",
        credential_scope_ref: "credential-scope://tenant/example/docs",
        runtime_family: "direct",
        manifest_digest: "sha256:abc",
        required_scopes: ["documents_read"],
        connector_auth_binding_kind: "connection_id"
      })

    assert request.operation_role == :source_read
    assert request.operation_class == :source_read
    assert request.binding_kind == :connection_id
    assert descriptor.side_effect_class == :read
    assert descriptor.connector_auth_binding_kind == :connection_id
  end

  test "accepts platform operation roles and binding kinds used by generic packs" do
    for {operation_role, operation_class, binding_kind} <- [
          {:source_publish, :source_write, :source_publication},
          {:runtime_session, :runtime_session, :runtime},
          {:evidence_collection, :evidence_collection, :evidence},
          {:runtime_tool, :runtime_tool_invocation, :runtime_tool},
          {:resource_effect, :resource_effect, :resource_effect}
        ] do
      request =
        OperationLookupRequest.new!(%{
          connector_ref: "connector://example/docs",
          manifest_ref: "manifest://example/docs/v1",
          operation_ref: "example.operation.#{operation_role}",
          operation_role: operation_role,
          operation_class: operation_class,
          binding_kind: binding_kind,
          required_runtime_family: "direct",
          binding_ref: "binding://tenant/example/docs/#{binding_kind}",
          pack_ref: "pack://example/doc-review",
          pack_revision: "1",
          credential_scope_ref: "credential-scope://tenant/example/docs"
        })

      assert request.operation_role == operation_role
      assert request.operation_class == operation_class
      assert request.binding_kind == binding_kind
    end
  end

  test "rejects missing required request fields" do
    assert {:error, %ArgumentError{} = error} =
             OperationLookupRequest.new(%{connector_ref: "connector://example/docs"})

    assert String.contains?(Exception.message(error), "manifest_ref")
  end
end
