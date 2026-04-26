defmodule Jido.Integration.V2.Connectors.Linear.OperationCatalog do
  @moduledoc false

  alias Jido.Integration.V2.Connectors.Linear.Operation
  alias Jido.Integration.V2.Connectors.Linear.PublishedSurface
  alias Jido.Integration.V2.OperationSpec

  @policy_defaults %{
    environment: %{allowed: [:prod, :staging]},
    sandbox: %{
      level: :standard,
      egress: :restricted,
      approvals: :auto
    }
  }

  @type entry :: %{
          allowed_tools: [String.t()],
          artifact_slug: String.t(),
          document: String.t(),
          event_type: String.t(),
          failure_event_type: String.t(),
          operation: atom(),
          operation_id: String.t(),
          operation_name: String.t(),
          permission_bundle: [String.t()],
          published?: boolean(),
          rollout_phase: atom()
        }

  @spec operations() :: [OperationSpec.t()]
  def operations do
    [
      comments_create_operation(),
      comments_update_operation(),
      graphql_execute_operation(),
      issues_list_operation(),
      issues_retrieve_operation(),
      issues_update_operation(),
      users_get_self_operation(),
      workflow_states_list_operation()
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

  defp users_get_self_operation do
    operation_spec(
      operation_id: "linear.users.get_self",
      name: "users_get_self",
      description: "Resolve the current Linear user through the active lease.",
      permission_bundle: ["read"],
      allowed_tools: ["linear.api.users.get_self"],
      upstream: %{method: "POST", path: "/graphql"},
      metadata: %{
        operation: :users_get_self,
        event_type: "connector.linear.users.get_self.completed",
        failure_event_type: "connector.linear.users.get_self.failed",
        artifact_slug: "users_get_self",
        rollout_phase: :a0,
        publication: :public,
        document: PublishedSurface.document("linear.users.get_self"),
        operation_name: PublishedSurface.operation_name("linear.users.get_self")
      }
    )
  end

  defp issues_list_operation do
    operation_spec(
      operation_id: "linear.issues.list",
      name: "issues_list",
      description: "List Linear issues for the narrow A0 issue-workflow slice.",
      permission_bundle: ["read"],
      allowed_tools: ["linear.api.issues.list"],
      upstream: %{method: "POST", path: "/graphql"},
      metadata: %{
        operation: :issues_list,
        event_type: "connector.linear.issues.list.completed",
        failure_event_type: "connector.linear.issues.list.failed",
        artifact_slug: "issues_list",
        rollout_phase: :a0,
        publication: :public,
        document: PublishedSurface.document("linear.issues.list"),
        operation_name: PublishedSurface.operation_name("linear.issues.list")
      }
    )
  end

  defp issues_retrieve_operation do
    operation_spec(
      operation_id: "linear.issues.retrieve",
      name: "issues_retrieve",
      description: "Retrieve a Linear issue with workflow-state detail for updates.",
      permission_bundle: ["read"],
      allowed_tools: ["linear.api.issues.retrieve"],
      upstream: %{method: "POST", path: "/graphql"},
      metadata: %{
        operation: :issues_retrieve,
        event_type: "connector.linear.issues.retrieve.completed",
        failure_event_type: "connector.linear.issues.retrieve.failed",
        artifact_slug: "issues_retrieve",
        rollout_phase: :a0,
        publication: :public,
        document: PublishedSurface.document("linear.issues.retrieve"),
        operation_name: PublishedSurface.operation_name("linear.issues.retrieve")
      }
    )
  end

  defp comments_create_operation do
    operation_spec(
      operation_id: "linear.comments.create",
      name: "comments_create",
      description: "Create a Linear comment on an issue.",
      permission_bundle: ["write"],
      allowed_tools: ["linear.api.comments.create"],
      upstream: %{method: "POST", path: "/graphql"},
      metadata: %{
        operation: :comments_create,
        event_type: "connector.linear.comments.create.completed",
        failure_event_type: "connector.linear.comments.create.failed",
        artifact_slug: "comments_create",
        rollout_phase: :a0,
        publication: :public,
        document: PublishedSurface.document("linear.comments.create"),
        operation_name: PublishedSurface.operation_name("linear.comments.create")
      }
    )
  end

  defp comments_update_operation do
    operation_spec(
      operation_id: "linear.comments.update",
      name: "comments_update",
      description: "Update a stable Linear workpad or progress comment.",
      permission_bundle: ["write"],
      allowed_tools: ["linear.api.comments.update"],
      upstream: %{method: "POST", path: "/graphql"},
      metadata: %{
        operation: :comments_update,
        event_type: "connector.linear.comments.update.completed",
        failure_event_type: "connector.linear.comments.update.failed",
        artifact_slug: "comments_update",
        rollout_phase: :a0,
        publication: :public,
        document: PublishedSurface.document("linear.comments.update"),
        operation_name: PublishedSurface.operation_name("linear.comments.update")
      }
    )
  end

  defp graphql_execute_operation do
    operation_spec(
      operation_id: "linear.graphql.execute",
      name: "graphql_execute",
      description:
        "Execute a governed connector-local Linear GraphQL document through the lease-bound SDK client.",
      permission_bundle: ["read", "write"],
      allowed_tools: ["linear.api.graphql.execute"],
      upstream: %{method: "POST", path: "/graphql"},
      metadata: %{
        operation: :graphql_execute,
        event_type: "connector.linear.graphql.execute.completed",
        failure_event_type: "connector.linear.graphql.execute.failed",
        artifact_slug: "graphql_execute",
        rollout_phase: :a0,
        publication: :public,
        document: PublishedSurface.document("linear.graphql.execute"),
        operation_name: PublishedSurface.operation_name("linear.graphql.execute")
      }
    )
  end

  defp issues_update_operation do
    operation_spec(
      operation_id: "linear.issues.update",
      name: "issues_update",
      description: "Update a Linear issue through the narrow A0 workflow fields.",
      permission_bundle: ["write"],
      allowed_tools: ["linear.api.issues.update"],
      upstream: %{method: "POST", path: "/graphql"},
      metadata: %{
        operation: :issues_update,
        event_type: "connector.linear.issues.update.completed",
        failure_event_type: "connector.linear.issues.update.failed",
        artifact_slug: "issues_update",
        rollout_phase: :a0,
        publication: :public,
        document: PublishedSurface.document("linear.issues.update"),
        operation_name: PublishedSurface.operation_name("linear.issues.update")
      }
    )
  end

  defp workflow_states_list_operation do
    operation_spec(
      operation_id: "linear.workflow_states.list",
      name: "workflow_states_list",
      description: "List Linear workflow states by ids, names, type, and team filter.",
      permission_bundle: ["read"],
      allowed_tools: ["linear.api.workflow_states.list"],
      upstream: %{method: "POST", path: "/graphql"},
      metadata: %{
        operation: :workflow_states_list,
        event_type: "connector.linear.workflow_states.list.completed",
        failure_event_type: "connector.linear.workflow_states.list.failed",
        artifact_slug: "workflow_states_list",
        rollout_phase: :a0,
        publication: :public,
        document: PublishedSurface.document("linear.workflow_states.list"),
        operation_name: PublishedSurface.operation_name("linear.workflow_states.list")
      }
    )
  end

  defp operation_spec(opts) do
    operation_id = Keyword.fetch!(opts, :operation_id)
    permission_bundle = Keyword.fetch!(opts, :permission_bundle)
    allowed_tools = Keyword.fetch!(opts, :allowed_tools)
    metadata = Keyword.fetch!(opts, :metadata)
    consumer_surface = PublishedSurface.consumer_surface(operation_id)

    OperationSpec.new!(%{
      operation_id: operation_id,
      name: Keyword.fetch!(opts, :name),
      display_name: Keyword.get(opts, :display_name, display_name(operation_id)),
      description: Keyword.fetch!(opts, :description),
      runtime_class: :direct,
      transport_mode: :sdk,
      handler: Operation,
      input_schema: PublishedSurface.input_schema(operation_id),
      output_schema: PublishedSurface.output_schema(operation_id),
      permissions: %{
        permission_bundle: permission_bundle,
        required_scopes: permission_bundle
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
      jido: jido_surface(consumer_surface),
      metadata: metadata
    })
  end

  defp jido_surface(%{mode: :common, action_name: action_name}) do
    %{action: %{name: action_name}}
  end

  defp jido_surface(_consumer_surface), do: %{}

  defp entry(%OperationSpec{} = operation) do
    %{
      operation_id: operation.operation_id,
      operation: operation.metadata.operation,
      document: operation.metadata.document,
      operation_name: operation.metadata.operation_name,
      artifact_slug: operation.metadata.artifact_slug,
      event_type: operation.metadata.event_type,
      failure_event_type: operation.metadata.failure_event_type,
      allowed_tools: get_in(operation.policy, [:sandbox, :allowed_tools]) || [],
      rollout_phase: operation.metadata.rollout_phase,
      published?: published?(operation),
      permission_bundle: operation.permissions.permission_bundle
    }
  end

  defp published?(%OperationSpec{} = operation) do
    Map.get(operation.metadata, :publication) == :public
  end

  defp display_name(operation_id) do
    operation_id
    |> String.split(".")
    |> Enum.drop(1)
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
