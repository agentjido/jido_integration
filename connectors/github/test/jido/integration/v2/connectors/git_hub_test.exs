defmodule Jido.Integration.V2.Connectors.GitHubTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.GitHub.Fixtures
  alias Jido.Integration.V2.Connectors.GitHub.Operation
  alias Jido.Integration.V2.Connectors.GitHub.OperationCatalog
  alias Jido.Integration.V2.OperationSpec

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
  @normalized_surface_expectations %{
    "github.comment.create" => {"comment.create", "comment_create"},
    "github.comment.update" => {"comment.update", "comment_update"},
    "github.issue.close" => {"work_item.close", "work_item_close"},
    "github.issue.create" => {"work_item.create", "work_item_create"},
    "github.issue.fetch" => {"work_item.fetch", "work_item_fetch"},
    "github.issue.label" => {"work_item.label_add", "work_item_label_add"},
    "github.issue.list" => {"work_item.list", "work_item_list"},
    "github.issue.update" => {"work_item.update", "work_item_update"}
  }

  test "publishes the A0 direct catalog slice as authored operation specs plus derived capabilities" do
    manifest = GitHub.manifest()

    assert manifest.connector == "github"
    assert manifest.auth.binding_kind == :connection_id
    assert manifest.auth.auth_type == :api_token
    assert manifest.auth.default_profile == "personal_access_token"
    assert manifest.auth.secret_names == []
    assert manifest.catalog.display_name == "GitHub"
    assert manifest.catalog.publication == :public
    assert manifest.runtime_families == [:direct]
    assert manifest.metadata.provider_sdk == :github_ex
    assert manifest.metadata.published_slice == :a0_issue_workflows

    assert manifest.auth.install == %{
             required: true,
             profiles: ["personal_access_token"],
             hosted_callback_supported: false,
             callback_route_kind: nil,
             state_required: false,
             pkce_supported: false,
             expires_in_seconds: nil,
             metadata: %{approval: :manual_token_entry}
           }

    assert manifest.auth.reauth == %{
             supported: false,
             profiles: [],
             hosted_callback_supported: false,
             state_required: false,
             pkce_supported: false,
             metadata: %{}
           }

    assert [profile] = manifest.auth.supported_profiles
    assert profile.id == "personal_access_token"
    assert profile.auth_type == :api_token
    assert profile.subject_kind == :user
    assert profile.install_required == true
    assert profile.grant_types == [:manual_token]
    assert profile.refresh_supported == false
    assert profile.revoke_supported == false
    assert profile.reauth_supported == false
    assert profile.durable_secret_fields == ["access_token"]
    assert profile.lease_fields == ["access_token"]
    assert profile.management_modes == [:manual]
    assert profile.required_scopes == ["repo"]

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

    Enum.each(manifest.operations, fn operation ->
      {normalized_id, action_name} =
        Map.fetch!(@normalized_surface_expectations, operation.operation_id)

      assert operation.consumer_surface.mode == :common
      assert operation.consumer_surface.normalized_id == normalized_id
      assert operation.consumer_surface.action_name == action_name
      assert operation.schema_policy.input == :defined
      assert operation.schema_policy.output == :defined
    end)
  end

  test "authors the A0 slice as rich operation specs and derives the executable catalog from them" do
    operations = OperationCatalog.published_operations()
    entries = OperationCatalog.entries()

    assert Enum.all?(operations, &match?(%OperationSpec{}, &1))

    assert Enum.map(operations, & &1.operation_id) ==
             @published_capability_ids

    assert Enum.map(OperationCatalog.published_entries(), & &1.operation_id) ==
             @published_capability_ids

    assert Enum.all?(entries, & &1.published?)

    Enum.each(Fixtures.specs(), fn spec ->
      operation = OperationCatalog.fetch_operation!(spec.capability_id)

      assert {:ok, _parsed_input} = Zoi.parse(operation.input_schema, spec.input)
      assert {:ok, _parsed_output} = Zoi.parse(operation.output_schema, spec.output)
      assert is_binary(operation.display_name)
      refute operation.description =~ "GitHub API projection for"
    end)

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("github.issue.fetch").input_schema,
               %{repo: "agentjido/jido_integration_v2"}
             )

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("github.issue.fetch").input_schema,
               %{repo: "agentjido/jido_integration_v2/extra", issue_number: 42}
             )

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("github.issue.fetch").input_schema,
               %{repo: "agentjido/jido_integration_v2", issue_number: 0}
             )

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("github.issue.create").input_schema,
               %{repo: "agentjido/jido_integration_v2"}
             )

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("github.comment.update").input_schema,
               %{repo: "agentjido/jido_integration_v2", comment_id: 901}
             )

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("github.comment.update").input_schema,
               %{repo: "agentjido/jido_integration_v2", comment_id: 0, body: "Edited comment"}
             )

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("github.issue.list").input_schema,
               %{repo: "agentjido/jido_integration_v2", per_page: 0, page: 1}
             )

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("github.issue.list").input_schema,
               %{repo: "agentjido/jido_integration_v2", per_page: 2, page: -1}
             )

    assert OperationCatalog.fetch!("github.issue.close").sdk_function == :update
    assert OperationCatalog.fetch!("github.issue.label").sdk_function == :add_labels

    assert Enum.all?(entries, fn entry ->
             assert Code.ensure_loaded?(entry.sdk_module)
             function_exported?(entry.sdk_module, entry.sdk_function, 2)
           end)
  end
end
