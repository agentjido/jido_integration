defmodule Jido.Integration.V2.Connectors.GitHub.CapabilityCatalog do
  @moduledoc false

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Connectors.GitHub.Operation

  @connector_id "github"
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
      capability_id: "github.comment.create",
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
      capability_id: "github.comment.update",
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
      capability_id: "github.issue.close",
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
      capability_id: "github.issue.create",
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
      capability_id: "github.issue.fetch",
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
      capability_id: "github.issue.label",
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
      capability_id: "github.issue.list",
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
      capability_id: "github.issue.update",
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
          capability_id: String.t(),
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
  def entries do
    Enum.map(@entries, &Map.put(&1, :permission_bundle, @permission_bundle))
  end

  @spec published_entries() :: [entry()]
  def published_entries do
    Enum.filter(entries(), & &1.published?)
  end

  @spec fetch!(String.t()) :: entry()
  def fetch!(capability_id) when is_binary(capability_id) do
    Enum.find(entries(), &(&1.capability_id == capability_id)) ||
      raise KeyError, key: capability_id, term: __MODULE__
  end

  @spec published_capabilities() :: [Capability.t()]
  def published_capabilities do
    published_entries()
    |> Enum.map(&capability/1)
    |> Enum.sort_by(& &1.id)
  end

  defp capability(entry) do
    Capability.new!(%{
      id: entry.capability_id,
      connector: @connector_id,
      runtime_class: :direct,
      kind: :operation,
      transport_profile: :sdk,
      handler: Operation,
      metadata: %{
        operation: entry.operation,
        sdk_module: entry.sdk_module,
        sdk_function: entry.sdk_function,
        actor_field: entry.actor_field,
        permission_bundle: entry.permission_bundle,
        required_scopes: entry.permission_bundle,
        event_type: entry.event_type,
        failure_event_type: entry.failure_event_type,
        artifact_slug: entry.artifact_slug,
        rollout_phase: entry.rollout_phase,
        upstream: %{
          method: entry.method,
          path: entry.path
        },
        policy:
          put_in(
            @policy_defaults,
            [:sandbox, :allowed_tools],
            entry.allowed_tools
          )
      }
    })
  end
end
