defmodule Jido.Integration.V2.Connectors.GitHub.OperationCatalog do
  @moduledoc false

  alias Jido.Integration.V2.Connectors.GitHub.Operation
  alias Jido.Integration.V2.OperationSpec

  @permission_bundle ["repo"]
  @policy_defaults %{
    environment: %{allowed: [:prod, :staging]},
    sandbox: %{
      level: :standard,
      egress: :restricted,
      approvals: :auto
    }
  }

  @entries [
    %{
      operation_id: "github.comment.create",
      sdk_module: GitHubEx.Issues,
      sdk_function: :create_comment,
      operation: :comment_create,
      actor_field: :created_by,
      artifact_slug: "comment_create",
      event_type: "connector.github.comment.created",
      failure_event_type: "connector.github.comment.create.failed",
      allowed_tools: ["github.api.comment.create"],
      method: "POST",
      path: "/repos/{owner}/{repo}/issues/{issue_number}/comments",
      rollout_phase: :a0,
      published?: true
    },
    %{
      operation_id: "github.comment.update",
      sdk_module: GitHubEx.Issues,
      sdk_function: :update_comment,
      operation: :comment_update,
      actor_field: :updated_by,
      artifact_slug: "comment_update",
      event_type: "connector.github.comment.updated",
      failure_event_type: "connector.github.comment.update.failed",
      allowed_tools: ["github.api.comment.update"],
      method: "PATCH",
      path: "/repos/{owner}/{repo}/issues/comments/{comment_id}",
      rollout_phase: :a0,
      published?: true
    },
    %{
      operation_id: "github.issue.close",
      sdk_module: GitHubEx.Issues,
      sdk_function: :update,
      operation: :issue_close,
      actor_field: :closed_by,
      artifact_slug: "issue_close",
      event_type: "connector.github.issue.closed",
      failure_event_type: "connector.github.issue.close.failed",
      allowed_tools: ["github.api.issue.close"],
      method: "PATCH",
      path: "/repos/{owner}/{repo}/issues/{issue_number}",
      rollout_phase: :a0,
      published?: true
    },
    %{
      operation_id: "github.issue.create",
      sdk_module: GitHubEx.Issues,
      sdk_function: :create,
      operation: :issue_create,
      actor_field: :opened_by,
      artifact_slug: "issue_create",
      event_type: "connector.github.issue.created",
      failure_event_type: "connector.github.issue.create.failed",
      allowed_tools: ["github.api.issue.create"],
      method: "POST",
      path: "/repos/{owner}/{repo}/issues",
      rollout_phase: :a0,
      published?: true
    },
    %{
      operation_id: "github.issue.fetch",
      sdk_module: GitHubEx.Issues,
      sdk_function: :get,
      operation: :issue_fetch,
      actor_field: :fetched_by,
      artifact_slug: "issue_fetch",
      event_type: "connector.github.issue.fetched",
      failure_event_type: "connector.github.issue.fetch.failed",
      allowed_tools: ["github.api.issue.fetch"],
      method: "GET",
      path: "/repos/{owner}/{repo}/issues/{issue_number}",
      rollout_phase: :a0,
      published?: true
    },
    %{
      operation_id: "github.issue.label",
      sdk_module: GitHubEx.Issues,
      sdk_function: :add_labels,
      operation: :issue_label,
      actor_field: :labeled_by,
      artifact_slug: "issue_label",
      event_type: "connector.github.issue.labeled",
      failure_event_type: "connector.github.issue.label.failed",
      allowed_tools: ["github.api.issue.label"],
      method: "POST",
      path: "/repos/{owner}/{repo}/issues/{issue_number}/labels",
      rollout_phase: :a0,
      published?: true
    },
    %{
      operation_id: "github.issue.list",
      sdk_module: GitHubEx.Issues,
      sdk_function: :list_for_repo,
      operation: :issue_list,
      actor_field: :listed_by,
      artifact_slug: "issue_list",
      event_type: "connector.github.issue.listed",
      failure_event_type: "connector.github.issue.list.failed",
      allowed_tools: ["github.api.issue.list"],
      method: "GET",
      path: "/repos/{owner}/{repo}/issues",
      rollout_phase: :a0,
      published?: true
    },
    %{
      operation_id: "github.issue.update",
      sdk_module: GitHubEx.Issues,
      sdk_function: :update,
      operation: :issue_update,
      actor_field: :updated_by,
      artifact_slug: "issue_update",
      event_type: "connector.github.issue.updated",
      failure_event_type: "connector.github.issue.update.failed",
      allowed_tools: ["github.api.issue.update"],
      method: "PATCH",
      path: "/repos/{owner}/{repo}/issues/{issue_number}",
      rollout_phase: :a0,
      published?: true
    }
  ]

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
          permission_bundle: [String.t()] | nil,
          published?: boolean(),
          rollout_phase: atom(),
          sdk_function: atom(),
          sdk_module: module()
        }

  @spec entries() :: [entry()]
  def entries, do: Enum.map(@entries, &Map.put(&1, :permission_bundle, @permission_bundle))

  @spec published_entries() :: [entry()]
  def published_entries do
    Enum.filter(entries(), & &1.published?)
  end

  @spec fetch!(String.t()) :: entry()
  def fetch!(operation_id) when is_binary(operation_id) do
    Enum.find(entries(), &(&1.operation_id == operation_id)) ||
      raise KeyError, key: operation_id, term: __MODULE__
  end

  @spec published_operations() :: [OperationSpec.t()]
  def published_operations do
    published_entries()
    |> Enum.map(&operation_spec/1)
    |> Enum.sort_by(& &1.operation_id)
  end

  defp operation_spec(entry) do
    OperationSpec.new!(%{
      operation_id: entry.operation_id,
      name: Atom.to_string(entry.operation),
      display_name: display_name(entry.operation_id),
      description: "GitHub API projection for #{entry.operation_id}",
      runtime_class: :direct,
      transport_mode: :sdk,
      handler: Operation,
      input_schema: Zoi.map(description: "Input payload for #{entry.operation_id}"),
      output_schema: Zoi.map(description: "Output payload for #{entry.operation_id}"),
      permissions: %{
        permission_bundle: entry.permission_bundle,
        required_scopes: entry.permission_bundle
      },
      policy:
        put_in(
          @policy_defaults,
          [:sandbox, :allowed_tools],
          entry.allowed_tools
        ),
      upstream: %{
        method: entry.method,
        path: entry.path
      },
      jido: %{
        action: %{
          name: String.replace(entry.operation_id, ".", "_")
        }
      },
      metadata: %{
        operation: entry.operation,
        sdk_module: entry.sdk_module,
        sdk_function: entry.sdk_function,
        actor_field: entry.actor_field,
        event_type: entry.event_type,
        failure_event_type: entry.failure_event_type,
        artifact_slug: entry.artifact_slug,
        rollout_phase: entry.rollout_phase
      }
    })
  end

  defp display_name(operation_id) do
    operation_id
    |> String.split(".")
    |> Enum.drop(1)
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
