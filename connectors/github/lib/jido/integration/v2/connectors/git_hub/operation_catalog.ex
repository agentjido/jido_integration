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
      comment_create_operation(),
      comment_update_operation(),
      issue_close_operation(),
      issue_create_operation(),
      issue_fetch_operation(),
      issue_label_operation(),
      issue_list_operation(),
      issue_update_operation()
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

  defp operation_spec(opts) do
    operation_id = Keyword.fetch!(opts, :operation_id)
    allowed_tools = Keyword.fetch!(opts, :allowed_tools)
    metadata = Keyword.fetch!(opts, :metadata)

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
      jido: %{
        action: %{
          name: String.replace(operation_id, ".", "_")
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

  defp strict_object(fields) do
    Contracts.strict_object!(fields)
  end

  defp repo_schema do
    Zoi.string(description: "Repository in owner/repo form")
    |> Zoi.regex(@repo_regex, message: "Repository must be in owner/repo form")
  end

  defp request_opts_schema do
    Zoi.any()
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

  defp display_name(operation_id) do
    operation_id
    |> String.split(".")
    |> Enum.drop(1)
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
