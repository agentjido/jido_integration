defmodule Jido.Integration.V2.Connectors.GitHub.OperationCatalog do
  @moduledoc false

  alias Jido.Integration.V2.Connectors.GitHub.Operation
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.OperationSpec

  @repo_regex ~r/\A[^\/\s]+\/[^\/\s]+\z/

  @permission_bundle ["repo"]
  @policy_defaults %{
    environment: %{allowed: [:prod, :staging]},
    sandbox: %{
      level: :standard,
      egress: :restricted,
      approvals: :auto
    }
  }

  @type entry :: %{
          actor_field: atom(),
          allowed_tools: [String.t()],
          artifact_slug: String.t(),
          operation_id: String.t(),
          event_type: String.t(),
          failure_event_type: String.t(),
          method: String.t(),
          operation: atom(),
          path: String.t(),
          permission_bundle: [String.t()],
          published?: boolean(),
          rollout_phase: atom(),
          sdk_function: atom(),
          sdk_module: module()
        }

  @spec operations() :: [OperationSpec.t()]
  def operations do
    [
      check_runs_list_for_ref_operation(),
      comment_create_operation(),
      comment_update_operation(),
      commit_statuses_get_combined_operation(),
      commit_statuses_list_operation(),
      commits_list_operation(),
      issue_close_operation(),
      issue_create_operation(),
      issue_fetch_operation(),
      issue_label_operation(),
      issue_list_operation(),
      issue_update_operation(),
      pr_create_operation(),
      pr_fetch_operation(),
      pr_list_operation(),
      pr_review_create_operation(),
      pr_review_comment_create_operation(),
      pr_review_comments_list_operation(),
      pr_reviews_list_operation(),
      pr_update_operation()
    ]
    |> Enum.sort_by(& &1.operation_id)
  end

  @spec published_operations() :: [OperationSpec.t()]
  def published_operations do
    Enum.filter(operations(), &published?/1)
  end

  @spec fetch_operation!(String.t()) :: OperationSpec.t()
  def fetch_operation!(operation_id) when is_binary(operation_id) do
    Enum.find(operations(), &(&1.operation_id == operation_id)) ||
      raise KeyError, key: operation_id, term: __MODULE__
  end

  @spec entries() :: [entry()]
  def entries do
    Enum.map(operations(), &entry/1)
  end

  @spec published_entries() :: [entry()]
  def published_entries do
    published_operations()
    |> Enum.map(&entry/1)
  end

  @spec fetch!(String.t()) :: entry()
  def fetch!(operation_id) when is_binary(operation_id) do
    operation_id
    |> fetch_operation!()
    |> entry()
  end

  defp check_runs_list_for_ref_operation do
    operation_spec(
      operation_id: "github.check_runs.list_for_ref",
      name: "check_runs_list_for_ref",
      description: "List GitHub check runs for a commit ref.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          ref: ref_schema(),
          check_name: Zoi.string() |> Zoi.optional(),
          status: Zoi.string() |> Zoi.optional(),
          filter: Zoi.string() |> Zoi.optional(),
          app_id: positive_integer_schema() |> Zoi.optional(),
          per_page: positive_integer_schema() |> Zoi.optional(),
          page: positive_integer_schema() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          ref: ref_schema(),
          total_count: Zoi.integer(),
          check_runs: Zoi.list(check_run_schema()),
          listed_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.check_runs.list_for_ref"],
      upstream: %{
        method: "GET",
        path: "/repos/{owner}/{repo}/commits/{ref}/check-runs"
      },
      metadata: %{
        operation: :check_runs_list_for_ref,
        sdk_module: GitHubEx.Checks,
        sdk_function: :list_for_ref,
        actor_field: :listed_by,
        event_type: "connector.github.check_runs.listed",
        failure_event_type: "connector.github.check_runs.list.failed",
        artifact_slug: "check_runs_list_for_ref",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp commit_statuses_get_combined_operation do
    operation_spec(
      operation_id: "github.commit.statuses.get_combined",
      name: "commit_statuses_get_combined",
      description: "Fetch the combined GitHub commit status for a ref.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          ref: ref_schema(),
          per_page: positive_integer_schema() |> Zoi.optional(),
          page: positive_integer_schema() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          ref: ref_schema(),
          sha: ref_schema(),
          state: Zoi.string(),
          total_count: Zoi.integer(),
          statuses: Zoi.list(commit_status_schema()),
          fetched_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.commit.statuses.get_combined"],
      upstream: %{
        method: "GET",
        path: "/repos/{owner}/{repo}/commits/{ref}/status"
      },
      metadata: %{
        operation: :commit_statuses_get_combined,
        sdk_module: GitHubEx.Repos,
        sdk_function: :get_combined_status_for_ref,
        actor_field: :fetched_by,
        event_type: "connector.github.commit.statuses.combined_fetched",
        failure_event_type: "connector.github.commit.statuses.get_combined.failed",
        artifact_slug: "commit_statuses_get_combined",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp commit_statuses_list_operation do
    operation_spec(
      operation_id: "github.commit.statuses.list",
      name: "commit_statuses_list",
      description: "List GitHub commit statuses for a ref.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          ref: ref_schema(),
          per_page: positive_integer_schema() |> Zoi.optional(),
          page: positive_integer_schema() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          ref: ref_schema(),
          total_count: Zoi.integer(),
          statuses: Zoi.list(commit_status_schema()),
          listed_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.commit.statuses.list"],
      upstream: %{
        method: "GET",
        path: "/repos/{owner}/{repo}/commits/{ref}/statuses"
      },
      metadata: %{
        operation: :commit_statuses_list,
        sdk_module: GitHubEx.Repos,
        sdk_function: :list_commit_statuses_for_ref,
        actor_field: :listed_by,
        event_type: "connector.github.commit.statuses.listed",
        failure_event_type: "connector.github.commit.statuses.list.failed",
        artifact_slug: "commit_statuses_list",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp commits_list_operation do
    operation_spec(
      operation_id: "github.commits.list",
      name: "commits_list",
      description: "List GitHub commits with filters used as evidence refs.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          sha: Zoi.string() |> Zoi.optional(),
          path: Zoi.string() |> Zoi.optional(),
          author: Zoi.string() |> Zoi.optional(),
          committer: Zoi.string() |> Zoi.optional(),
          since: Zoi.string() |> Zoi.optional(),
          until: Zoi.string() |> Zoi.optional(),
          per_page: positive_integer_schema() |> Zoi.optional(),
          page: positive_integer_schema() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          sha: Zoi.string() |> Zoi.nullable(),
          path: Zoi.string() |> Zoi.nullable(),
          page: positive_integer_schema(),
          per_page: positive_integer_schema(),
          total_count: Zoi.integer(),
          commits: Zoi.list(commit_schema()),
          listed_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.commits.list"],
      upstream: %{
        method: "GET",
        path: "/repos/{owner}/{repo}/commits"
      },
      metadata: %{
        operation: :commits_list,
        sdk_module: GitHubEx.Repos,
        sdk_function: :list_commits,
        actor_field: :listed_by,
        event_type: "connector.github.commits.listed",
        failure_event_type: "connector.github.commits.list.failed",
        artifact_slug: "commits_list",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp issue_list_operation do
    operation_spec(
      operation_id: "github.issue.list",
      name: "issue_list",
      description: "List GitHub issues for a repository.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          state: Zoi.enum(["open", "closed", "all"]) |> Zoi.optional(),
          per_page: positive_integer_schema() |> Zoi.optional(),
          page: positive_integer_schema() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          state: Zoi.string(),
          page: positive_integer_schema(),
          per_page: positive_integer_schema(),
          total_count: Zoi.integer(),
          issues: Zoi.list(issue_summary_schema()),
          listed_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.issue.list"],
      upstream: %{
        method: "GET",
        path: "/repos/{owner}/{repo}/issues"
      },
      metadata: %{
        operation: :issue_list,
        sdk_module: GitHubEx.Issues,
        sdk_function: :list_for_repo,
        actor_field: :listed_by,
        event_type: "connector.github.issue.listed",
        failure_event_type: "connector.github.issue.list.failed",
        artifact_slug: "issue_list",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp issue_fetch_operation do
    operation_spec(
      operation_id: "github.issue.fetch",
      name: "issue_fetch",
      description: "Fetch a GitHub issue by repository and issue number.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          issue_number: positive_integer_schema(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          issue_number: positive_integer_schema(),
          title: Zoi.string(),
          body: Zoi.string() |> Zoi.nullable(),
          state: Zoi.string(),
          labels: string_list_schema(),
          fetched_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.issue.fetch"],
      upstream: %{
        method: "GET",
        path: "/repos/{owner}/{repo}/issues/{issue_number}"
      },
      metadata: %{
        operation: :issue_fetch,
        sdk_module: GitHubEx.Issues,
        sdk_function: :get,
        actor_field: :fetched_by,
        event_type: "connector.github.issue.fetched",
        failure_event_type: "connector.github.issue.fetch.failed",
        artifact_slug: "issue_fetch",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp issue_create_operation do
    operation_spec(
      operation_id: "github.issue.create",
      name: "issue_create",
      description: "Create a GitHub issue in a repository.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          title: Zoi.string(),
          body: Zoi.string() |> Zoi.nullish(),
          labels: string_list_schema() |> Zoi.optional(),
          assignees: string_list_schema() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          issue_number: positive_integer_schema(),
          title: Zoi.string(),
          body: Zoi.string() |> Zoi.nullable(),
          state: Zoi.string(),
          labels: string_list_schema(),
          assignees: string_list_schema(),
          opened_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.issue.create"],
      upstream: %{
        method: "POST",
        path: "/repos/{owner}/{repo}/issues"
      },
      metadata: %{
        operation: :issue_create,
        sdk_module: GitHubEx.Issues,
        sdk_function: :create,
        actor_field: :opened_by,
        event_type: "connector.github.issue.created",
        failure_event_type: "connector.github.issue.create.failed",
        artifact_slug: "issue_create",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp issue_update_operation do
    operation_spec(
      operation_id: "github.issue.update",
      name: "issue_update",
      description: "Update a GitHub issue's editable fields.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          issue_number: positive_integer_schema(),
          title: Zoi.string() |> Zoi.optional(),
          body: Zoi.string() |> Zoi.nullish(),
          state: Zoi.string() |> Zoi.optional(),
          labels: string_list_schema() |> Zoi.optional(),
          assignees: string_list_schema() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          issue_number: positive_integer_schema(),
          title: Zoi.string() |> Zoi.nullable(),
          body: Zoi.string() |> Zoi.nullable(),
          state: Zoi.string(),
          labels: string_list_schema(),
          assignees: string_list_schema(),
          updated_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.issue.update"],
      upstream: %{
        method: "PATCH",
        path: "/repos/{owner}/{repo}/issues/{issue_number}"
      },
      metadata: %{
        operation: :issue_update,
        sdk_module: GitHubEx.Issues,
        sdk_function: :update,
        actor_field: :updated_by,
        event_type: "connector.github.issue.updated",
        failure_event_type: "connector.github.issue.update.failed",
        artifact_slug: "issue_update",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp issue_label_operation do
    operation_spec(
      operation_id: "github.issue.label",
      name: "issue_label",
      description: "Add labels to an existing GitHub issue.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          issue_number: positive_integer_schema(),
          labels: string_list_schema(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          issue_number: positive_integer_schema(),
          labels: string_list_schema(),
          labeled_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.issue.label"],
      upstream: %{
        method: "POST",
        path: "/repos/{owner}/{repo}/issues/{issue_number}/labels"
      },
      metadata: %{
        operation: :issue_label,
        sdk_module: GitHubEx.Issues,
        sdk_function: :add_labels,
        actor_field: :labeled_by,
        event_type: "connector.github.issue.labeled",
        failure_event_type: "connector.github.issue.label.failed",
        artifact_slug: "issue_label",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp issue_close_operation do
    operation_spec(
      operation_id: "github.issue.close",
      name: "issue_close",
      description: "Close a GitHub issue by setting its state to closed.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          issue_number: positive_integer_schema(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          issue_number: positive_integer_schema(),
          state: Zoi.string(),
          closed_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.issue.close"],
      upstream: %{
        method: "PATCH",
        path: "/repos/{owner}/{repo}/issues/{issue_number}"
      },
      metadata: %{
        operation: :issue_close,
        sdk_module: GitHubEx.Issues,
        sdk_function: :update,
        actor_field: :closed_by,
        event_type: "connector.github.issue.closed",
        failure_event_type: "connector.github.issue.close.failed",
        artifact_slug: "issue_close",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp comment_create_operation do
    operation_spec(
      operation_id: "github.comment.create",
      name: "comment_create",
      description: "Create a comment on a GitHub issue.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          issue_number: positive_integer_schema(),
          body: Zoi.string(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          issue_number: positive_integer_schema(),
          comment_id: positive_integer_schema(),
          body: Zoi.string(),
          created_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.comment.create"],
      upstream: %{
        method: "POST",
        path: "/repos/{owner}/{repo}/issues/{issue_number}/comments"
      },
      metadata: %{
        operation: :comment_create,
        sdk_module: GitHubEx.Issues,
        sdk_function: :create_comment,
        actor_field: :created_by,
        event_type: "connector.github.comment.created",
        failure_event_type: "connector.github.comment.create.failed",
        artifact_slug: "comment_create",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp comment_update_operation do
    operation_spec(
      operation_id: "github.comment.update",
      name: "comment_update",
      description: "Update an existing GitHub issue comment.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          comment_id: positive_integer_schema(),
          body: Zoi.string(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          comment_id: positive_integer_schema(),
          body: Zoi.string(),
          updated_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.comment.update"],
      upstream: %{
        method: "PATCH",
        path: "/repos/{owner}/{repo}/issues/comments/{comment_id}"
      },
      metadata: %{
        operation: :comment_update,
        sdk_module: GitHubEx.Issues,
        sdk_function: :update_comment,
        actor_field: :updated_by,
        event_type: "connector.github.comment.updated",
        failure_event_type: "connector.github.comment.update.failed",
        artifact_slug: "comment_update",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp pr_create_operation do
    operation_spec(
      operation_id: "github.pr.create",
      name: "pr_create",
      description: "Create a GitHub pull request through the active lease.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          title: ref_schema(),
          body: Zoi.string() |> Zoi.nullish(),
          head: ref_schema(),
          base: ref_schema(),
          draft: Zoi.boolean() |> Zoi.optional(),
          maintainer_can_modify: Zoi.boolean() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema: pull_request_output_schema(:opened_by),
      allowed_tools: ["github.api.pr.create"],
      upstream: %{
        method: "POST",
        path: "/repos/{owner}/{repo}/pulls"
      },
      metadata: %{
        operation: :pr_create,
        sdk_module: GitHubEx.Pulls,
        sdk_function: :create,
        actor_field: :opened_by,
        event_type: "connector.github.pr.created",
        failure_event_type: "connector.github.pr.create.failed",
        artifact_slug: "pr_create",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp pr_fetch_operation do
    operation_spec(
      operation_id: "github.pr.fetch",
      name: "pr_fetch",
      description: "Fetch a GitHub pull request by repository and PR number.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          pull_number: positive_integer_schema(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema: pull_request_output_schema(:fetched_by),
      allowed_tools: ["github.api.pr.fetch"],
      upstream: %{
        method: "GET",
        path: "/repos/{owner}/{repo}/pulls/{pull_number}"
      },
      metadata: %{
        operation: :pr_fetch,
        sdk_module: GitHubEx.Pulls,
        sdk_function: :get,
        actor_field: :fetched_by,
        event_type: "connector.github.pr.fetched",
        failure_event_type: "connector.github.pr.fetch.failed",
        artifact_slug: "pr_fetch",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp pr_list_operation do
    operation_spec(
      operation_id: "github.pr.list",
      name: "pr_list",
      description: "List GitHub pull requests for a repository.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          state: Zoi.enum(["open", "closed", "all"]) |> Zoi.optional(),
          head: Zoi.string() |> Zoi.optional(),
          base: Zoi.string() |> Zoi.optional(),
          sort: Zoi.enum(["created", "updated", "popularity", "long-running"]) |> Zoi.optional(),
          direction: Zoi.enum(["asc", "desc"]) |> Zoi.optional(),
          per_page: positive_integer_schema() |> Zoi.optional(),
          page: positive_integer_schema() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          state: Zoi.string(),
          page: positive_integer_schema(),
          per_page: positive_integer_schema(),
          total_count: Zoi.integer(),
          pull_requests: Zoi.list(pull_request_summary_schema()),
          listed_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.pr.list"],
      upstream: %{
        method: "GET",
        path: "/repos/{owner}/{repo}/pulls"
      },
      metadata: %{
        operation: :pr_list,
        sdk_module: GitHubEx.Pulls,
        sdk_function: :list,
        actor_field: :listed_by,
        event_type: "connector.github.pr.listed",
        failure_event_type: "connector.github.pr.list.failed",
        artifact_slug: "pr_list",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp pr_update_operation do
    operation_spec(
      operation_id: "github.pr.update",
      name: "pr_update",
      description: "Update a GitHub pull request's editable fields.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          pull_number: positive_integer_schema(),
          title: Zoi.string() |> Zoi.optional(),
          body: Zoi.string() |> Zoi.nullish(),
          state: Zoi.string() |> Zoi.optional(),
          base: Zoi.string() |> Zoi.optional(),
          maintainer_can_modify: Zoi.boolean() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema: pull_request_output_schema(:updated_by),
      allowed_tools: ["github.api.pr.update"],
      upstream: %{
        method: "PATCH",
        path: "/repos/{owner}/{repo}/pulls/{pull_number}"
      },
      metadata: %{
        operation: :pr_update,
        sdk_module: GitHubEx.Pulls,
        sdk_function: :update,
        actor_field: :updated_by,
        event_type: "connector.github.pr.updated",
        failure_event_type: "connector.github.pr.update.failed",
        artifact_slug: "pr_update",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp pr_reviews_list_operation do
    operation_spec(
      operation_id: "github.pr.reviews.list",
      name: "pr_reviews_list",
      description: "List GitHub pull request reviews.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          pull_number: positive_integer_schema(),
          per_page: positive_integer_schema() |> Zoi.optional(),
          page: positive_integer_schema() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          pull_number: positive_integer_schema(),
          total_count: Zoi.integer(),
          reviews: Zoi.list(review_schema()),
          listed_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.pr.reviews.list"],
      upstream: %{
        method: "GET",
        path: "/repos/{owner}/{repo}/pulls/{pull_number}/reviews"
      },
      metadata: %{
        operation: :pr_reviews_list,
        sdk_module: GitHubEx.Pulls,
        sdk_function: :list_reviews,
        actor_field: :listed_by,
        event_type: "connector.github.pr.reviews.listed",
        failure_event_type: "connector.github.pr.reviews.list.failed",
        artifact_slug: "pr_reviews_list",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp pr_review_comments_list_operation do
    operation_spec(
      operation_id: "github.pr.review_comments.list",
      name: "pr_review_comments_list",
      description: "List GitHub pull request review comments as thread evidence.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          pull_number: positive_integer_schema(),
          sort: Zoi.enum(["created", "updated"]) |> Zoi.optional(),
          direction: Zoi.enum(["asc", "desc"]) |> Zoi.optional(),
          since: Zoi.string() |> Zoi.optional(),
          per_page: positive_integer_schema() |> Zoi.optional(),
          page: positive_integer_schema() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          pull_number: positive_integer_schema(),
          total_count: Zoi.integer(),
          comments: Zoi.list(review_comment_schema()),
          listed_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.pr.review_comments.list"],
      upstream: %{
        method: "GET",
        path: "/repos/{owner}/{repo}/pulls/{pull_number}/comments"
      },
      metadata: %{
        operation: :pr_review_comments_list,
        sdk_module: GitHubEx.Pulls,
        sdk_function: :list_review_comments,
        actor_field: :listed_by,
        event_type: "connector.github.pr.review_comments.listed",
        failure_event_type: "connector.github.pr.review_comments.list.failed",
        artifact_slug: "pr_review_comments_list",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp pr_review_create_operation do
    operation_spec(
      operation_id: "github.pr.review.create",
      name: "pr_review_create",
      description: "Publish a GitHub pull request review.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          pull_number: positive_integer_schema(),
          body: Zoi.string() |> Zoi.nullish(),
          event: Zoi.enum(["APPROVE", "REQUEST_CHANGES", "COMMENT"]) |> Zoi.optional(),
          comments: Zoi.list(Zoi.map(description: "Inline review comment")) |> Zoi.optional(),
          commit_id: Zoi.string() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          pull_number: positive_integer_schema(),
          review: review_schema(),
          created_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.pr.review.create"],
      upstream: %{
        method: "POST",
        path: "/repos/{owner}/{repo}/pulls/{pull_number}/reviews"
      },
      metadata: %{
        operation: :pr_review_create,
        sdk_module: GitHubEx.Pulls,
        sdk_function: :create_review,
        actor_field: :created_by,
        event_type: "connector.github.pr.review.created",
        failure_event_type: "connector.github.pr.review.create.failed",
        artifact_slug: "pr_review_create",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp pr_review_comment_create_operation do
    operation_spec(
      operation_id: "github.pr.review_comment.create",
      name: "pr_review_comment_create",
      description: "Publish a GitHub pull request inline review comment.",
      input_schema:
        strict_object(
          repo: repo_schema(),
          pull_number: positive_integer_schema(),
          body: Zoi.string(),
          commit_id: ref_schema(),
          path: ref_schema(),
          position: positive_integer_schema() |> Zoi.optional(),
          line: positive_integer_schema() |> Zoi.optional(),
          side: Zoi.string() |> Zoi.optional(),
          start_line: positive_integer_schema() |> Zoi.optional(),
          start_side: Zoi.string() |> Zoi.optional(),
          request_opts: request_opts_schema() |> Zoi.optional()
        ),
      output_schema:
        strict_object(
          repo: repo_schema(),
          pull_number: positive_integer_schema(),
          comment: review_comment_schema(),
          created_by: Zoi.string(),
          auth_binding: auth_binding_schema()
        ),
      allowed_tools: ["github.api.pr.review_comment.create"],
      upstream: %{
        method: "POST",
        path: "/repos/{owner}/{repo}/pulls/{pull_number}/comments"
      },
      metadata: %{
        operation: :pr_review_comment_create,
        sdk_module: GitHubEx.Pulls,
        sdk_function: :create_review_comment,
        actor_field: :created_by,
        event_type: "connector.github.pr.review_comment.created",
        failure_event_type: "connector.github.pr.review_comment.create.failed",
        artifact_slug: "pr_review_comment_create",
        rollout_phase: :a0,
        publication: :public
      }
    )
  end

  defp operation_spec(opts) do
    operation_id = Keyword.fetch!(opts, :operation_id)
    allowed_tools = Keyword.fetch!(opts, :allowed_tools)
    metadata = Keyword.fetch!(opts, :metadata)
    consumer_surface = common_consumer_surface(operation_id)

    OperationSpec.new!(%{
      operation_id: operation_id,
      name: Keyword.fetch!(opts, :name),
      display_name: Keyword.get(opts, :display_name, display_name(operation_id)),
      description: Keyword.fetch!(opts, :description),
      runtime_class: :direct,
      transport_mode: :sdk,
      handler: Operation,
      input_schema: Keyword.fetch!(opts, :input_schema),
      output_schema: Keyword.fetch!(opts, :output_schema),
      permissions: %{
        permission_bundle: @permission_bundle,
        required_scopes: @permission_bundle
      },
      policy:
        put_in(
          @policy_defaults,
          [:sandbox, :allowed_tools],
          allowed_tools
        ),
      upstream: Keyword.fetch!(opts, :upstream),
      consumer_surface: consumer_surface,
      schema_policy: %{input: :defined, output: :defined},
      jido: %{
        action: %{
          name: consumer_surface.action_name
        }
      },
      metadata: metadata
    })
  end

  defp entry(%OperationSpec{} = operation) do
    %{
      operation_id: operation.operation_id,
      sdk_module: operation.metadata.sdk_module,
      sdk_function: operation.metadata.sdk_function,
      operation: operation.metadata.operation,
      actor_field: operation.metadata.actor_field,
      artifact_slug: operation.metadata.artifact_slug,
      event_type: operation.metadata.event_type,
      failure_event_type: operation.metadata.failure_event_type,
      allowed_tools: get_in(operation.policy, [:sandbox, :allowed_tools]) || [],
      method: operation.upstream.method,
      path: operation.upstream.path,
      rollout_phase: operation.metadata.rollout_phase,
      published?: published?(operation),
      permission_bundle: operation.permissions.permission_bundle
    }
  end

  defp published?(%OperationSpec{} = operation) do
    Map.get(operation.metadata, :publication) == :public
  end

  defp common_consumer_surface("github.check_runs.list_for_ref"),
    do: %{mode: :common, normalized_id: "check_run.list", action_name: "check_run_list"}

  defp common_consumer_surface("github.commit.statuses.get_combined") do
    %{
      mode: :common,
      normalized_id: "commit_status.combined_fetch",
      action_name: "commit_status_combined_fetch"
    }
  end

  defp common_consumer_surface("github.commit.statuses.list"),
    do: %{mode: :common, normalized_id: "commit_status.list", action_name: "commit_status_list"}

  defp common_consumer_surface("github.commits.list"),
    do: %{mode: :common, normalized_id: "commit.list", action_name: "commit_list"}

  defp common_consumer_surface("github.issue.list"),
    do: %{mode: :common, normalized_id: "work_item.list", action_name: "work_item_list"}

  defp common_consumer_surface("github.issue.fetch"),
    do: %{mode: :common, normalized_id: "work_item.fetch", action_name: "work_item_fetch"}

  defp common_consumer_surface("github.issue.create"),
    do: %{mode: :common, normalized_id: "work_item.create", action_name: "work_item_create"}

  defp common_consumer_surface("github.issue.update"),
    do: %{mode: :common, normalized_id: "work_item.update", action_name: "work_item_update"}

  defp common_consumer_surface("github.issue.label"),
    do: %{
      mode: :common,
      normalized_id: "work_item.label_add",
      action_name: "work_item_label_add"
    }

  defp common_consumer_surface("github.issue.close"),
    do: %{mode: :common, normalized_id: "work_item.close", action_name: "work_item_close"}

  defp common_consumer_surface("github.comment.create"),
    do: %{mode: :common, normalized_id: "comment.create", action_name: "comment_create"}

  defp common_consumer_surface("github.comment.update"),
    do: %{mode: :common, normalized_id: "comment.update", action_name: "comment_update"}

  defp common_consumer_surface("github.pr.create"),
    do: %{mode: :common, normalized_id: "pull_request.create", action_name: "pull_request_create"}

  defp common_consumer_surface("github.pr.fetch"),
    do: %{mode: :common, normalized_id: "pull_request.fetch", action_name: "pull_request_fetch"}

  defp common_consumer_surface("github.pr.list"),
    do: %{mode: :common, normalized_id: "pull_request.list", action_name: "pull_request_list"}

  defp common_consumer_surface("github.pr.update"),
    do: %{mode: :common, normalized_id: "pull_request.update", action_name: "pull_request_update"}

  defp common_consumer_surface("github.pr.reviews.list") do
    %{
      mode: :common,
      normalized_id: "pull_request_review.list",
      action_name: "pull_request_review_list"
    }
  end

  defp common_consumer_surface("github.pr.review_comments.list") do
    %{
      mode: :common,
      normalized_id: "pull_request_review_comment.list",
      action_name: "pull_request_review_comment_list"
    }
  end

  defp common_consumer_surface("github.pr.review.create") do
    %{
      mode: :common,
      normalized_id: "pull_request_review.create",
      action_name: "pull_request_review_create"
    }
  end

  defp common_consumer_surface("github.pr.review_comment.create") do
    %{
      mode: :common,
      normalized_id: "pull_request_review_comment.create",
      action_name: "pull_request_review_comment_create"
    }
  end

  defp strict_object(fields) do
    Contracts.strict_object!(fields)
  end

  defp repo_schema do
    Zoi.string(description: "Repository in owner/repo form")
    |> Zoi.regex(@repo_regex, message: "Repository must be in owner/repo form")
  end

  defp request_opts_schema do
    Zoi.object(%{}, description: "Optional github_ex request options forwarded as a map")
  end

  defp ref_schema do
    Contracts.non_empty_string_schema("github.ref")
  end

  defp positive_integer_schema do
    Zoi.integer() |> Zoi.min(1)
  end

  defp string_list_schema do
    Zoi.list(Zoi.string())
  end

  defp auth_binding_schema do
    Zoi.string(description: "Redacted auth binding digest")
  end

  defp issue_summary_schema do
    strict_object(
      repo: repo_schema(),
      issue_number: positive_integer_schema(),
      title: Zoi.string(),
      state: Zoi.string(),
      labels: string_list_schema()
    )
  end

  defp pull_request_output_schema(actor_field) do
    [
      repo: repo_schema(),
      pull_number: positive_integer_schema(),
      title: Zoi.string(),
      body: Zoi.string() |> Zoi.nullable(),
      state: Zoi.string(),
      draft: Zoi.boolean(),
      merged: Zoi.boolean(),
      mergeable: Zoi.boolean() |> Zoi.nullable(),
      maintainer_can_modify: Zoi.boolean(),
      html_url: Zoi.string(),
      diff_url: Zoi.string() |> Zoi.nullable(),
      patch_url: Zoi.string() |> Zoi.nullable(),
      commits_url: Zoi.string() |> Zoi.nullable(),
      review_comments_url: Zoi.string() |> Zoi.nullable(),
      head: pr_ref_schema(),
      base: pr_ref_schema(),
      user: Zoi.string() |> Zoi.nullable(),
      labels: string_list_schema(),
      requested_reviewers: string_list_schema(),
      auth_binding: auth_binding_schema()
    ]
    |> Keyword.put(actor_field, Zoi.string())
    |> strict_object()
  end

  defp pull_request_summary_schema do
    strict_object(
      repo: repo_schema(),
      pull_number: positive_integer_schema(),
      title: Zoi.string(),
      body: Zoi.string() |> Zoi.nullable(),
      state: Zoi.string(),
      draft: Zoi.boolean(),
      merged: Zoi.boolean(),
      mergeable: Zoi.boolean() |> Zoi.nullable(),
      maintainer_can_modify: Zoi.boolean(),
      html_url: Zoi.string(),
      diff_url: Zoi.string() |> Zoi.nullable(),
      patch_url: Zoi.string() |> Zoi.nullable(),
      commits_url: Zoi.string() |> Zoi.nullable(),
      review_comments_url: Zoi.string() |> Zoi.nullable(),
      head: pr_ref_schema(),
      base: pr_ref_schema(),
      user: Zoi.string() |> Zoi.nullable(),
      labels: string_list_schema(),
      requested_reviewers: string_list_schema()
    )
  end

  defp pr_ref_schema do
    strict_object(
      ref: Zoi.string() |> Zoi.nullable(),
      sha: Zoi.string() |> Zoi.nullable(),
      repo: Zoi.string() |> Zoi.nullable()
    )
  end

  defp review_schema do
    strict_object(
      review_id: positive_integer_schema(),
      state: Zoi.string() |> Zoi.nullable(),
      body: Zoi.string() |> Zoi.nullable(),
      commit_id: Zoi.string() |> Zoi.nullable(),
      submitted_at: Zoi.string() |> Zoi.nullable(),
      user: Zoi.string() |> Zoi.nullable(),
      html_url: Zoi.string() |> Zoi.nullable()
    )
  end

  defp review_comment_schema do
    strict_object(
      comment_id: positive_integer_schema(),
      body: Zoi.string() |> Zoi.nullable(),
      path: Zoi.string() |> Zoi.nullable(),
      diff_hunk: Zoi.string() |> Zoi.nullable(),
      position: positive_integer_schema() |> Zoi.nullable(),
      line: positive_integer_schema() |> Zoi.nullable(),
      side: Zoi.string() |> Zoi.nullable(),
      start_line: positive_integer_schema() |> Zoi.nullable(),
      start_side: Zoi.string() |> Zoi.nullable(),
      commit_id: Zoi.string() |> Zoi.nullable(),
      original_commit_id: Zoi.string() |> Zoi.nullable(),
      in_reply_to_id: positive_integer_schema() |> Zoi.nullable(),
      pull_request_review_id: positive_integer_schema() |> Zoi.nullable(),
      user: Zoi.string() |> Zoi.nullable(),
      html_url: Zoi.string() |> Zoi.nullable()
    )
  end

  defp commit_status_schema do
    strict_object(
      status_id: positive_integer_schema(),
      state: Zoi.string(),
      context: Zoi.string() |> Zoi.nullable(),
      description: Zoi.string() |> Zoi.nullable(),
      target_url: Zoi.string() |> Zoi.nullable(),
      created_at: Zoi.string() |> Zoi.nullable(),
      updated_at: Zoi.string() |> Zoi.nullable()
    )
  end

  defp check_run_schema do
    strict_object(
      check_run_id: positive_integer_schema(),
      name: Zoi.string(),
      head_sha: Zoi.string() |> Zoi.nullable(),
      status: Zoi.string() |> Zoi.nullable(),
      conclusion: Zoi.string() |> Zoi.nullable(),
      html_url: Zoi.string() |> Zoi.nullable(),
      details_url: Zoi.string() |> Zoi.nullable(),
      started_at: Zoi.string() |> Zoi.nullable(),
      completed_at: Zoi.string() |> Zoi.nullable(),
      app_slug: Zoi.string() |> Zoi.nullable()
    )
  end

  defp commit_schema do
    strict_object(
      sha: Zoi.string(),
      html_url: Zoi.string() |> Zoi.nullable(),
      message: Zoi.string() |> Zoi.nullable(),
      author_name: Zoi.string() |> Zoi.nullable(),
      author_email: Zoi.string() |> Zoi.nullable(),
      author_date: Zoi.string() |> Zoi.nullable(),
      committer_name: Zoi.string() |> Zoi.nullable(),
      committer_email: Zoi.string() |> Zoi.nullable(),
      committer_date: Zoi.string() |> Zoi.nullable()
    )
  end

  defp display_name(operation_id) do
    operation_id
    |> String.split(".")
    |> Enum.drop(1)
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
