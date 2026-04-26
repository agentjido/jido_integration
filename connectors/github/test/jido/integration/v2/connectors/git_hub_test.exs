defmodule Jido.Integration.V2.Connectors.GitHubTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.GitHub.Fixtures
  alias Jido.Integration.V2.Connectors.GitHub.Operation
  alias Jido.Integration.V2.Connectors.GitHub.OperationCatalog
  alias Jido.Integration.V2.OperationSpec

  @published_capability_ids [
    "github.check_runs.list_for_ref",
    "github.comment.create",
    "github.comment.update",
    "github.commit.statuses.get_combined",
    "github.commit.statuses.list",
    "github.commits.list",
    "github.issue.close",
    "github.issue.create",
    "github.issue.fetch",
    "github.issue.label",
    "github.issue.list",
    "github.issue.update",
    "github.pr.create",
    "github.pr.fetch",
    "github.pr.list",
    "github.pr.review.create",
    "github.pr.review_comment.create",
    "github.pr.review_comments.list",
    "github.pr.reviews.list",
    "github.pr.update"
  ]

  @sdk_expectations %{
    "github.check_runs.list_for_ref" =>
      {GitHubEx.Checks, :list_for_ref, ["github.api.check_runs.list_for_ref"]},
    "github.comment.create" => {GitHubEx.Issues, :create_comment, ["github.api.comment.create"]},
    "github.comment.update" => {GitHubEx.Issues, :update_comment, ["github.api.comment.update"]},
    "github.commit.statuses.get_combined" =>
      {GitHubEx.Repos, :get_combined_status_for_ref, ["github.api.commit.statuses.get_combined"]},
    "github.commit.statuses.list" =>
      {GitHubEx.Repos, :list_commit_statuses_for_ref, ["github.api.commit.statuses.list"]},
    "github.commits.list" => {GitHubEx.Repos, :list_commits, ["github.api.commits.list"]},
    "github.issue.close" => {GitHubEx.Issues, :update, ["github.api.issue.close"]},
    "github.issue.create" => {GitHubEx.Issues, :create, ["github.api.issue.create"]},
    "github.issue.fetch" => {GitHubEx.Issues, :get, ["github.api.issue.fetch"]},
    "github.issue.label" => {GitHubEx.Issues, :add_labels, ["github.api.issue.label"]},
    "github.issue.list" => {GitHubEx.Issues, :list_for_repo, ["github.api.issue.list"]},
    "github.issue.update" => {GitHubEx.Issues, :update, ["github.api.issue.update"]},
    "github.pr.create" => {GitHubEx.Pulls, :create, ["github.api.pr.create"]},
    "github.pr.fetch" => {GitHubEx.Pulls, :get, ["github.api.pr.fetch"]},
    "github.pr.list" => {GitHubEx.Pulls, :list, ["github.api.pr.list"]},
    "github.pr.review.create" =>
      {GitHubEx.Pulls, :create_review, ["github.api.pr.review.create"]},
    "github.pr.review_comment.create" =>
      {GitHubEx.Pulls, :create_review_comment, ["github.api.pr.review_comment.create"]},
    "github.pr.review_comments.list" =>
      {GitHubEx.Pulls, :list_review_comments, ["github.api.pr.review_comments.list"]},
    "github.pr.reviews.list" => {GitHubEx.Pulls, :list_reviews, ["github.api.pr.reviews.list"]},
    "github.pr.update" => {GitHubEx.Pulls, :update, ["github.api.pr.update"]}
  }
  @normalized_surface_expectations %{
    "github.check_runs.list_for_ref" => {"check_run.list", "check_run_list"},
    "github.comment.create" => {"comment.create", "comment_create"},
    "github.comment.update" => {"comment.update", "comment_update"},
    "github.commit.statuses.get_combined" =>
      {"commit_status.combined_fetch", "commit_status_combined_fetch"},
    "github.commit.statuses.list" => {"commit_status.list", "commit_status_list"},
    "github.commits.list" => {"commit.list", "commit_list"},
    "github.issue.close" => {"work_item.close", "work_item_close"},
    "github.issue.create" => {"work_item.create", "work_item_create"},
    "github.issue.fetch" => {"work_item.fetch", "work_item_fetch"},
    "github.issue.label" => {"work_item.label_add", "work_item_label_add"},
    "github.issue.list" => {"work_item.list", "work_item_list"},
    "github.issue.update" => {"work_item.update", "work_item_update"},
    "github.pr.create" => {"pull_request.create", "pull_request_create"},
    "github.pr.fetch" => {"pull_request.fetch", "pull_request_fetch"},
    "github.pr.list" => {"pull_request.list", "pull_request_list"},
    "github.pr.review.create" => {"pull_request_review.create", "pull_request_review_create"},
    "github.pr.review_comment.create" =>
      {"pull_request_review_comment.create", "pull_request_review_comment_create"},
    "github.pr.review_comments.list" =>
      {"pull_request_review_comment.list", "pull_request_review_comment_list"},
    "github.pr.reviews.list" => {"pull_request_review.list", "pull_request_review_list"},
    "github.pr.update" => {"pull_request.update", "pull_request_update"}
  }

  test "publishes the A0 direct catalog slice as authored operation specs plus derived capabilities" do
    manifest = GitHub.manifest()

    assert manifest.connector == "github"
    assert manifest.auth.binding_kind == :connection_id
    assert manifest.auth.auth_type == :api_token
    assert manifest.auth.default_profile == "personal_access_token"
    assert manifest.auth.management_modes == [:external_secret, :hosted, :manual]
    assert manifest.auth.requested_scopes == ["repo"]
    assert manifest.auth.durable_secret_fields == ["access_token", "refresh_token"]
    assert manifest.auth.lease_fields == ["access_token"]
    assert manifest.auth.secret_names == []
    assert manifest.catalog.display_name == "GitHub"
    assert manifest.catalog.publication == :public
    assert manifest.runtime_families == [:direct]
    assert manifest.metadata.provider_sdk == :github_ex
    assert manifest.metadata.published_slice == :a0_pr_review_status_workflows

    assert manifest.auth.install == %{
             required: true,
             profiles: ["oauth_user", "personal_access_token"],
             hosted_callback_supported: true,
             callback_route_kind: "oauth_callback",
             state_required: true,
             pkce_supported: false,
             expires_in_seconds: nil,
             metadata: %{
               completion_modes: [:hosted_callback, :manual_callback],
               approval_by_profile: %{
                 oauth_user: :browser_oauth,
                 personal_access_token: :manual_token_entry
               }
             }
           }

    assert manifest.auth.reauth == %{
             supported: true,
             profiles: ["oauth_user"],
             hosted_callback_supported: true,
             state_required: true,
             pkce_supported: false,
             metadata: %{reuse_install_path: true}
           }

    assert Enum.map(manifest.auth.supported_profiles, & &1.id) == [
             "oauth_user",
             "personal_access_token"
           ]

    oauth_profile =
      Enum.find(manifest.auth.supported_profiles, &(&1.id == "oauth_user"))

    assert oauth_profile.auth_type == :oauth2
    assert oauth_profile.subject_kind == :user
    assert oauth_profile.install_required == true
    assert oauth_profile.grant_types == [:authorization_code, :refresh_token]
    assert oauth_profile.callback_required == true
    assert oauth_profile.pkce_required == false
    assert oauth_profile.refresh_supported == true
    assert oauth_profile.revoke_supported == true
    assert oauth_profile.reauth_supported == true
    assert oauth_profile.external_secret_supported == true
    assert oauth_profile.durable_secret_fields == ["access_token", "refresh_token"]
    assert oauth_profile.lease_fields == ["access_token"]
    assert oauth_profile.management_modes == [:external_secret, :hosted, :manual]
    assert oauth_profile.required_scopes == ["repo"]

    pat_profile =
      Enum.find(manifest.auth.supported_profiles, &(&1.id == "personal_access_token"))

    assert pat_profile.auth_type == :api_token
    assert pat_profile.subject_kind == :user
    assert pat_profile.install_required == true
    assert pat_profile.grant_types == [:manual_token]
    assert pat_profile.refresh_supported == false
    assert pat_profile.revoke_supported == false
    assert pat_profile.reauth_supported == false
    assert pat_profile.external_secret_supported == true
    assert pat_profile.durable_secret_fields == ["access_token"]
    assert pat_profile.lease_fields == ["access_token"]
    assert pat_profile.management_modes == [:external_secret, :manual]
    assert pat_profile.required_scopes == ["repo"]

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

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("github.pr.fetch").input_schema,
               %{repo: "agentjido/jido_integration_v2", pull_number: 0}
             )

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("github.pr.create").input_schema,
               %{repo: "agentjido/jido_integration_v2", title: "Missing branch refs"}
             )

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("github.pr.review_comment.create").input_schema,
               %{
                 repo: "agentjido/jido_integration_v2",
                 pull_number: 17,
                 body: "Missing commit and path"
               }
             )

    assert {:error, _reason} =
             Zoi.parse(
               OperationCatalog.fetch_operation!("github.check_runs.list_for_ref").input_schema,
               %{repo: "agentjido/jido_integration_v2", ref: "", page: 1}
             )

    assert OperationCatalog.fetch!("github.issue.close").sdk_function == :update
    assert OperationCatalog.fetch!("github.issue.label").sdk_function == :add_labels
    assert OperationCatalog.fetch!("github.pr.review.create").sdk_function == :create_review

    assert Enum.all?(entries, fn entry ->
             assert Code.ensure_loaded?(entry.sdk_module)
             function_exported?(entry.sdk_module, entry.sdk_function, 2)
           end)
  end
end
