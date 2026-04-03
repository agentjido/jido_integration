defmodule Jido.Integration.V2.Connectors.Linear.PublishedSurface do
  @moduledoc false

  alias Jido.Integration.V2.Contracts

  @viewer_query """
  query JidoLinearViewer {
    viewer {
      id
      name
      email
    }
  }
  """

  @issues_list_query """
  query JidoLinearIssuesList($filter: IssueFilter, $first: Int, $after: String) {
    issues(filter: $filter, first: $first, after: $after) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        id
        identifier
        title
        priority
        url
        createdAt
        updatedAt
        state {
          id
          name
          type
        }
        assignee {
          id
          name
          email
        }
        project {
          id
          name
          slugId
          url
        }
        team {
          id
          key
          name
        }
      }
    }
  }
  """

  @issue_retrieve_query """
  query JidoLinearIssueRetrieve($issueId: String!) {
    issue(id: $issueId) {
      id
      identifier
      title
      description
      priority
      branchName
      url
      createdAt
      updatedAt
      labels {
        nodes {
          name
        }
      }
      state {
        id
        name
        type
      }
      assignee {
        id
        name
        email
      }
      project {
        id
        name
        slugId
        url
      }
      team {
        id
        key
        name
        states(first: 50) {
          nodes {
            id
            name
            type
          }
        }
      }
    }
  }
  """

  @comment_create_mutation """
  mutation JidoLinearCommentCreate($issueId: String!, $body: String!) {
    commentCreate(input: {issueId: $issueId, body: $body}) {
      success
      comment {
        id
        body
        issue {
          id
          identifier
        }
      }
    }
  }
  """

  @issue_update_mutation """
  mutation JidoLinearIssueUpdate($issueId: String!, $input: IssueUpdateInput!) {
    issueUpdate(id: $issueId, input: $input) {
      success
      issue {
        id
        identifier
        title
        url
        updatedAt
        state {
          id
          name
          type
        }
      }
    }
  }
  """

  @spec consumer_surface(String.t()) :: map()
  def consumer_surface("linear.users.get_self") do
    %{mode: :common, normalized_id: "users.get_self", action_name: "users_get_self"}
  end

  def consumer_surface("linear.issues.list") do
    %{mode: :common, normalized_id: "work_item.list", action_name: "work_item_list"}
  end

  def consumer_surface("linear.issues.retrieve") do
    %{mode: :common, normalized_id: "work_item.fetch", action_name: "work_item_fetch"}
  end

  def consumer_surface("linear.comments.create") do
    %{mode: :common, normalized_id: "comment.create", action_name: "comment_create"}
  end

  def consumer_surface("linear.issues.update") do
    %{mode: :common, normalized_id: "work_item.update", action_name: "work_item_update"}
  end

  @spec document(String.t()) :: String.t()
  def document("linear.users.get_self"), do: @viewer_query
  def document("linear.issues.list"), do: @issues_list_query
  def document("linear.issues.retrieve"), do: @issue_retrieve_query
  def document("linear.comments.create"), do: @comment_create_mutation
  def document("linear.issues.update"), do: @issue_update_mutation

  @spec operation_name(String.t()) :: String.t()
  def operation_name("linear.users.get_self"), do: "JidoLinearViewer"
  def operation_name("linear.issues.list"), do: "JidoLinearIssuesList"
  def operation_name("linear.issues.retrieve"), do: "JidoLinearIssueRetrieve"
  def operation_name("linear.comments.create"), do: "JidoLinearCommentCreate"
  def operation_name("linear.issues.update"), do: "JidoLinearIssueUpdate"

  @spec input_schema(String.t()) :: Zoi.schema()
  def input_schema("linear.users.get_self") do
    strict_object([],
      description: "No input is required to resolve the current Linear user"
    )
  end

  def input_schema("linear.issues.list") do
    strict_object(
      [
        filter:
          strict_object(
            [
              project_slug: Zoi.string() |> Zoi.optional(),
              state_names: Zoi.list(Zoi.string()) |> Zoi.optional(),
              assignee_id: Zoi.string() |> Zoi.optional()
            ],
            description:
              "Optional candidate-issue filter for project, workflow state, and assignee"
          )
          |> Zoi.optional(),
        first: positive_integer_schema() |> Zoi.optional(),
        after: Zoi.string() |> Zoi.optional()
      ],
      description: "List Linear issues for candidate issue workflows"
    )
  end

  def input_schema("linear.issues.retrieve") do
    strict_object(
      [
        issue_id: Zoi.string()
      ],
      description: "Retrieve a Linear issue by its provider id"
    )
  end

  def input_schema("linear.comments.create") do
    strict_object(
      [
        issue_id: Zoi.string(),
        body: Zoi.string()
      ],
      description: "Create a Linear comment on an issue"
    )
  end

  def input_schema("linear.issues.update") do
    strict_object(
      [
        issue_id: Zoi.string(),
        state_id: Zoi.string() |> Zoi.optional(),
        title: Zoi.string() |> Zoi.optional(),
        description: Zoi.string() |> Zoi.nullish(),
        assignee_id: Zoi.string() |> Zoi.nullish()
      ],
      description: "Update a Linear issue with the narrow A0 workflow fields"
    )
  end

  @spec output_schema(String.t()) :: Zoi.schema()
  def output_schema("linear.users.get_self") do
    strict_object(
      [
        user: user_schema(),
        auth_binding: auth_binding_schema()
      ],
      description: "Current Linear user identity resolved from the active lease"
    )
  end

  def output_schema("linear.issues.list") do
    strict_object(
      [
        issues: Zoi.list(issue_summary_schema()),
        page_info: page_info_schema(),
        auth_binding: auth_binding_schema()
      ],
      description: "Candidate Linear issue list for the current filter"
    )
  end

  def output_schema("linear.issues.retrieve") do
    strict_object(
      [
        issue: issue_detail_schema(),
        auth_binding: auth_binding_schema()
      ],
      description: "Detailed Linear issue record including workflow-state helpers"
    )
  end

  def output_schema("linear.comments.create") do
    strict_object(
      [
        success: Zoi.boolean(),
        comment: comment_schema() |> Zoi.nullable(),
        auth_binding: auth_binding_schema()
      ],
      description: "Comment creation result returned by Linear"
    )
  end

  def output_schema("linear.issues.update") do
    strict_object(
      [
        success: Zoi.boolean(),
        issue: updated_issue_schema() |> Zoi.nullable(),
        auth_binding: auth_binding_schema()
      ],
      description: "Issue update result returned by Linear"
    )
  end

  defp issue_summary_schema do
    strict_object(
      id: Zoi.string(),
      identifier: Zoi.string(),
      title: Zoi.string(),
      priority: Zoi.integer() |> Zoi.nullable(),
      url: Zoi.string() |> Zoi.nullable(),
      created_at: Zoi.string() |> Zoi.nullable(),
      updated_at: Zoi.string() |> Zoi.nullable(),
      state: workflow_state_schema() |> Zoi.nullable(),
      assignee: user_schema() |> Zoi.nullable(),
      project: project_schema() |> Zoi.nullable(),
      team: team_summary_schema() |> Zoi.nullable()
    )
  end

  defp issue_detail_schema do
    strict_object(
      id: Zoi.string(),
      identifier: Zoi.string(),
      title: Zoi.string(),
      description: Zoi.string() |> Zoi.nullable(),
      priority: Zoi.integer() |> Zoi.nullable(),
      branch_name: Zoi.string() |> Zoi.nullable(),
      url: Zoi.string() |> Zoi.nullable(),
      created_at: Zoi.string() |> Zoi.nullable(),
      updated_at: Zoi.string() |> Zoi.nullable(),
      labels: Zoi.list(Zoi.string()),
      state: workflow_state_schema() |> Zoi.nullable(),
      assignee: user_schema() |> Zoi.nullable(),
      project: project_schema() |> Zoi.nullable(),
      team: team_detail_schema() |> Zoi.nullable()
    )
  end

  defp updated_issue_schema do
    strict_object(
      id: Zoi.string(),
      identifier: Zoi.string(),
      title: Zoi.string() |> Zoi.nullable(),
      url: Zoi.string() |> Zoi.nullable(),
      updated_at: Zoi.string() |> Zoi.nullable(),
      state: workflow_state_schema() |> Zoi.nullable()
    )
  end

  defp comment_schema do
    strict_object(
      id: Zoi.string(),
      body: Zoi.string() |> Zoi.nullable(),
      issue:
        strict_object(
          id: Zoi.string(),
          identifier: Zoi.string() |> Zoi.nullable()
        )
        |> Zoi.nullable()
    )
  end

  defp user_schema do
    strict_object(
      id: Zoi.string(),
      name: Zoi.string() |> Zoi.nullable(),
      email: Zoi.string() |> Zoi.nullable()
    )
  end

  defp project_schema do
    strict_object(
      id: Zoi.string(),
      name: Zoi.string() |> Zoi.nullable(),
      slug_id: Zoi.string() |> Zoi.nullable(),
      url: Zoi.string() |> Zoi.nullable()
    )
  end

  defp team_summary_schema do
    strict_object(
      id: Zoi.string(),
      key: Zoi.string() |> Zoi.nullable(),
      name: Zoi.string() |> Zoi.nullable()
    )
  end

  defp team_detail_schema do
    strict_object(
      id: Zoi.string(),
      key: Zoi.string() |> Zoi.nullable(),
      name: Zoi.string() |> Zoi.nullable(),
      workflow_states: Zoi.list(workflow_state_schema())
    )
  end

  defp workflow_state_schema do
    strict_object(
      id: Zoi.string(),
      name: Zoi.string() |> Zoi.nullable(),
      type: Zoi.string() |> Zoi.nullable()
    )
  end

  defp page_info_schema do
    strict_object(
      has_next_page: Zoi.boolean(),
      end_cursor: Zoi.string() |> Zoi.nullable()
    )
  end

  defp auth_binding_schema do
    Zoi.string(description: "Redacted auth binding digest")
  end

  defp positive_integer_schema do
    Zoi.integer() |> Zoi.min(1)
  end

  defp strict_object(fields, opts \\ []) do
    Contracts.strict_object!(fields, opts)
  end
end
