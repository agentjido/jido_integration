defmodule Jido.Integration.V2.Connectors.GitHubTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.GitHub.Operation
  alias Jido.Integration.V2.Connectors.GitHub.OperationCatalog

  @published_capability_ids [
    "github.comment.create",
    "github.comment.update",
    "github.issue.close",
    "github.issue.create",
    "github.issue.fetch",
    "github.issue.label",
    "github.issue.list",
    "github.issue.update"
  ]

  @sdk_expectations %{
    "github.comment.create" => {GitHubEx.Issues, :create_comment, ["github.api.comment.create"]},
    "github.comment.update" => {GitHubEx.Issues, :update_comment, ["github.api.comment.update"]},
    "github.issue.close" => {GitHubEx.Issues, :update, ["github.api.issue.close"]},
    "github.issue.create" => {GitHubEx.Issues, :create, ["github.api.issue.create"]},
    "github.issue.fetch" => {GitHubEx.Issues, :get, ["github.api.issue.fetch"]},
    "github.issue.label" => {GitHubEx.Issues, :add_labels, ["github.api.issue.label"]},
    "github.issue.list" => {GitHubEx.Issues, :list_for_repo, ["github.api.issue.list"]},
    "github.issue.update" => {GitHubEx.Issues, :update, ["github.api.issue.update"]}
  }

  test "publishes the A0 direct catalog slice as authored operation specs plus derived capabilities" do
    manifest = GitHub.manifest()

    assert manifest.connector == "github"
    assert manifest.auth.binding_kind == :connection_id
    assert manifest.auth.auth_type == :oauth2
    assert manifest.catalog.display_name == "GitHub"
    assert manifest.catalog.publication == :public
    assert manifest.runtime_families == [:direct]
    assert manifest.metadata.provider_sdk == :github_ex
    assert manifest.metadata.published_slice == :a0_issue_workflows

    assert Enum.map(manifest.operations, & &1.operation_id) ==
             Enum.sort(@published_capability_ids)

    assert Enum.map(manifest.capabilities, & &1.id) == Enum.sort(@published_capability_ids)

    Enum.each(manifest.capabilities, fn capability ->
      {sdk_module, sdk_function, allowed_tools} = Map.fetch!(@sdk_expectations, capability.id)

      assert capability.runtime_class == :direct
      assert capability.kind == :operation
      assert capability.transport_profile == :sdk
      assert capability.handler == Operation
      assert capability.metadata.sdk_module == sdk_module
      assert capability.metadata.sdk_function == sdk_function
      assert capability.metadata.permission_bundle == ["repo"]
      assert capability.metadata.required_scopes == ["repo"]
      assert capability.metadata.input_schema |> is_struct()
      assert capability.metadata.output_schema |> is_struct()
      assert capability.metadata.rollout_phase == :a0
      assert capability.metadata.event_type |> is_binary()
      assert capability.metadata.failure_event_type |> is_binary()
      assert capability.metadata.artifact_slug |> is_binary()
      assert capability.metadata.jido.action.name |> is_binary()
      assert capability.metadata.policy.environment.allowed == [:prod, :staging]
      assert capability.metadata.policy.sandbox.level == :standard
      assert capability.metadata.policy.sandbox.egress == :restricted
      assert capability.metadata.policy.sandbox.approvals == :auto
      assert capability.metadata.policy.sandbox.allowed_tools == allowed_tools
    end)
  end

  test "builds one authored operation catalog for the published github_ex issue surface" do
    entries = OperationCatalog.entries()

    assert Enum.map(OperationCatalog.published_entries(), & &1.operation_id) ==
             @published_capability_ids

    assert Enum.all?(entries, & &1.published?)

    assert OperationCatalog.fetch!("github.issue.close").sdk_function == :update
    assert OperationCatalog.fetch!("github.issue.label").sdk_function == :add_labels

    assert Enum.all?(entries, fn entry ->
             assert Code.ensure_loaded?(entry.sdk_module)
             function_exported?(entry.sdk_module, entry.sdk_function, 2)
           end)
  end
end
