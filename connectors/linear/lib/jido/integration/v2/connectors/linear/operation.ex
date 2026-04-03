defmodule Jido.Integration.V2.Connectors.Linear.Operation do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Connectors.Linear.ClientFactory
  alias Jido.Integration.V2.Connectors.Linear.ErrorMapper
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.RuntimeResult

  @spec run(map(), map()) :: {:ok, RuntimeResult.t()} | {:error, map(), RuntimeResult.t()}
  def run(input, context) when is_map(input) and is_map(context) do
    metadata = Map.fetch!(context.capability, :metadata)
    auth_binding = ClientFactory.auth_binding(context)

    with {:ok, client} <- ClientFactory.build(context),
         {:ok, variables} <- variables(metadata.operation, input),
         {:ok, %LinearSDK.Response{} = response} <-
           LinearSDK.execute_document(
             client,
             metadata.document,
             variables,
             request_opts(context)
           ),
         {:ok, output} <- normalize_output(metadata.operation, response.data, auth_binding) do
      {:ok, success_result(context, metadata, input, output, auth_binding)}
    else
      {:error, %LinearSDK.Error{} = error} ->
        error_result(context, metadata, input, auth_binding, ErrorMapper.from_linear_error(error))

      {:error, %{code: _code} = mapped_error} ->
        error_result(context, metadata, input, auth_binding, mapped_error)

      {:error, reason} ->
        error_result(context, metadata, input, auth_binding, ErrorMapper.from_reason(reason))
    end
  rescue
    error ->
      metadata = Map.fetch!(context.capability, :metadata)
      auth_binding = ClientFactory.auth_binding(context)
      error_result(context, metadata, input, auth_binding, ErrorMapper.from_reason(error))
  end

  defp variables(:users_get_self, _input), do: {:ok, %{}}

  defp variables(:issues_list, input) do
    filter =
      input
      |> optional_map(:filter)
      |> build_issue_filter()

    {:ok,
     %{}
     |> maybe_put("filter", filter)
     |> maybe_put("first", optional_value(input, :first))
     |> maybe_put("after", optional_value(input, :after))}
  end

  defp variables(:issues_retrieve, input) do
    {:ok, %{"issueId" => required_value(input, :issue_id)}}
  end

  defp variables(:comments_create, input) do
    {:ok,
     %{
       "issueId" => required_value(input, :issue_id),
       "body" => required_value(input, :body)
     }}
  end

  defp variables(:issues_update, input) do
    update_input =
      %{}
      |> maybe_put_present(input, :state_id, "stateId")
      |> maybe_put_present(input, :title, "title")
      |> maybe_put_present(input, :description, "description")
      |> maybe_put_present(input, :assignee_id, "assigneeId")

    if map_size(update_input) == 0 do
      {:error,
       ErrorMapper.preflight_validation(
         "Linear rejected linear.issues.update because no editable fields were supplied"
       )}
    else
      {:ok,
       %{
         "issueId" => required_value(input, :issue_id),
         "input" => update_input
       }}
    end
  end

  defp normalize_output(:users_get_self, %{"viewer" => viewer}, auth_binding) do
    {:ok,
     %{
       user: normalize_user(viewer),
       auth_binding: auth_binding
     }}
  end

  defp normalize_output(:issues_list, %{"issues" => issues}, auth_binding) do
    nodes = issues |> Map.get("nodes", []) |> Enum.map(&normalize_issue_summary/1)
    page_info = normalize_page_info(Map.get(issues, "pageInfo"))

    {:ok,
     %{
       issues: nodes,
       page_info: page_info,
       auth_binding: auth_binding
     }}
  end

  defp normalize_output(:issues_retrieve, %{"issue" => issue}, auth_binding) do
    {:ok,
     %{
       issue: normalize_issue_detail(issue),
       auth_binding: auth_binding
     }}
  end

  defp normalize_output(:comments_create, %{"commentCreate" => payload}, auth_binding) do
    {:ok,
     %{
       success: Map.get(payload, "success", false),
       comment: normalize_comment(Map.get(payload, "comment")),
       auth_binding: auth_binding
     }}
  end

  defp normalize_output(:issues_update, %{"issueUpdate" => payload}, auth_binding) do
    {:ok,
     %{
       success: Map.get(payload, "success", false),
       issue: normalize_updated_issue(Map.get(payload, "issue")),
       auth_binding: auth_binding
     }}
  end

  defp normalize_output(operation, data, _auth_binding) do
    {:error,
     ErrorMapper.preflight_validation(
       "Linear returned an unexpected payload for #{inspect(operation)}",
       issues: [data: data]
     )}
  end

  defp success_result(context, metadata, input, output, auth_binding) do
    RuntimeResult.new!(%{
      output: output,
      events: [
        %{
          type: metadata.event_type,
          stream: :control,
          payload: %{
            capability_id: context.capability.id,
            auth_binding: auth_binding
          }
        }
      ],
      artifacts: [
        ArtifactBuilder.build!(
          run_id: context.run_id,
          attempt_id: context.attempt_id,
          artifact_type: :tool_output,
          key: artifact_key(context, metadata.artifact_slug),
          content: %{
            capability_id: context.capability.id,
            request: Redaction.redact(input),
            response: output,
            auth_binding: auth_binding,
            execution_policy: context.policy_inputs.execution
          },
          metadata: %{
            connector: "linear",
            capability_id: context.capability.id,
            auth_binding: auth_binding
          }
        )
      ]
    })
  end

  defp error_result(context, metadata, input, auth_binding, mapped_error) do
    runtime_result =
      RuntimeResult.new!(%{
        output: %{
          capability_id: context.capability.id,
          auth_binding: auth_binding,
          error: mapped_error
        },
        events: [
          %{
            type: metadata.failure_event_type,
            stream: :control,
            level: :warn,
            payload: %{
              capability_id: context.capability.id,
              class: mapped_error.class,
              retryability: mapped_error.retryability,
              auth_binding: auth_binding
            }
          }
        ],
        artifacts: [
          ArtifactBuilder.build!(
            run_id: context.run_id,
            attempt_id: context.attempt_id,
            artifact_type: :tool_output,
            key: artifact_key(context, metadata.artifact_slug <> "_error"),
            content: %{
              capability_id: context.capability.id,
              request: Redaction.redact(input),
              error: mapped_error,
              auth_binding: auth_binding
            },
            metadata: %{
              connector: "linear",
              capability_id: context.capability.id,
              auth_binding: auth_binding
            }
          )
        ]
      })

    {:error, mapped_error, runtime_result}
  end

  defp request_opts(context) do
    context
    |> Map.get(:opts, %{})
    |> Contracts.get(:linear_request, [])
    |> normalize_runtime_opts()
  end

  defp build_issue_filter(%{} = filter) do
    %{}
    |> maybe_put("project", project_filter(filter))
    |> maybe_put("state", state_filter(filter))
    |> maybe_put("assignee", assignee_filter(filter))
    |> empty_map_to_nil()
  end

  defp project_filter(filter) do
    case present_filter_value(filter, :project_slug) do
      nil -> nil
      slug -> %{"slugId" => %{"eq" => slug}}
    end
  end

  defp state_filter(filter) do
    case present_filter_list(filter, :state_names) do
      [] -> nil
      state_names -> %{"name" => %{"in" => state_names}}
    end
  end

  defp assignee_filter(filter) do
    case present_filter_value(filter, :assignee_id) do
      nil -> nil
      assignee_id -> %{"id" => %{"eq" => assignee_id}}
    end
  end

  defp normalize_issue_summary(issue) do
    %{
      id: Map.get(issue, "id"),
      identifier: Map.get(issue, "identifier"),
      title: Map.get(issue, "title"),
      priority: Map.get(issue, "priority"),
      url: Map.get(issue, "url"),
      created_at: Map.get(issue, "createdAt"),
      updated_at: Map.get(issue, "updatedAt"),
      state: normalize_state(Map.get(issue, "state")),
      assignee: normalize_user(Map.get(issue, "assignee")),
      project: normalize_project(Map.get(issue, "project")),
      team: normalize_team_summary(Map.get(issue, "team"))
    }
  end

  defp normalize_issue_detail(issue) do
    %{
      id: Map.get(issue, "id"),
      identifier: Map.get(issue, "identifier"),
      title: Map.get(issue, "title"),
      description: Map.get(issue, "description"),
      priority: Map.get(issue, "priority"),
      branch_name: Map.get(issue, "branchName"),
      url: Map.get(issue, "url"),
      created_at: Map.get(issue, "createdAt"),
      updated_at: Map.get(issue, "updatedAt"),
      labels:
        issue
        |> Map.get("labels", %{})
        |> Map.get("nodes", [])
        |> Enum.map(&Map.get(&1, "name"))
        |> Enum.reject(&is_nil/1),
      state: normalize_state(Map.get(issue, "state")),
      assignee: normalize_user(Map.get(issue, "assignee")),
      project: normalize_project(Map.get(issue, "project")),
      team: normalize_team_detail(Map.get(issue, "team"))
    }
  end

  defp normalize_updated_issue(nil), do: nil

  defp normalize_updated_issue(issue) do
    %{
      id: Map.get(issue, "id"),
      identifier: Map.get(issue, "identifier"),
      title: Map.get(issue, "title"),
      url: Map.get(issue, "url"),
      updated_at: Map.get(issue, "updatedAt"),
      state: normalize_state(Map.get(issue, "state"))
    }
  end

  defp normalize_comment(nil), do: nil

  defp normalize_comment(comment) do
    %{
      id: Map.get(comment, "id"),
      body: Map.get(comment, "body"),
      issue:
        case Map.get(comment, "issue") do
          nil ->
            nil

          issue ->
            %{
              id: Map.get(issue, "id"),
              identifier: Map.get(issue, "identifier")
            }
        end
    }
  end

  defp normalize_page_info(page_info) when is_map(page_info) do
    %{
      has_next_page: Map.get(page_info, "hasNextPage", false),
      end_cursor: Map.get(page_info, "endCursor")
    }
  end

  defp normalize_page_info(_page_info) do
    %{
      has_next_page: false,
      end_cursor: nil
    }
  end

  defp normalize_state(nil), do: nil

  defp normalize_state(state) do
    %{
      id: Map.get(state, "id"),
      name: Map.get(state, "name"),
      type: Map.get(state, "type")
    }
  end

  defp normalize_user(nil), do: nil

  defp normalize_user(user) do
    %{
      id: Map.get(user, "id"),
      name: Map.get(user, "name"),
      email: Map.get(user, "email")
    }
  end

  defp normalize_project(nil), do: nil

  defp normalize_project(project) do
    %{
      id: Map.get(project, "id"),
      name: Map.get(project, "name"),
      slug_id: Map.get(project, "slugId"),
      url: Map.get(project, "url")
    }
  end

  defp normalize_team_summary(nil), do: nil

  defp normalize_team_summary(team) do
    %{
      id: Map.get(team, "id"),
      key: Map.get(team, "key"),
      name: Map.get(team, "name")
    }
  end

  defp normalize_team_detail(nil), do: nil

  defp normalize_team_detail(team) do
    %{
      id: Map.get(team, "id"),
      key: Map.get(team, "key"),
      name: Map.get(team, "name"),
      workflow_states:
        team
        |> Map.get("states", %{})
        |> Map.get("nodes", [])
        |> Enum.map(&normalize_state/1)
    }
  end

  defp artifact_key(context, slug) do
    "linear/#{context.run_id}/#{context.attempt_id}/#{slug}.term"
  end

  defp required_value(input, key) do
    optional_value(input, key)
  end

  defp optional_value(input, key) when is_map(input) do
    Map.get(input, key) || Map.get(input, Atom.to_string(key))
  end

  defp optional_map(input, key) do
    case optional_value(input, key) do
      value when is_map(value) -> value
      _other -> %{}
    end
  end

  defp present_filter_value(filter, key) do
    filter
    |> optional_value(key)
    |> present_string()
  end

  defp present_filter_list(filter, key) do
    case optional_value(filter, key) do
      values when is_list(values) -> Enum.reject(values, &(&1 in [nil, ""]))
      _other -> []
    end
  end

  defp present_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present_string(_value), do: nil

  defp empty_map_to_nil(map) when map_size(map) == 0, do: nil
  defp empty_map_to_nil(map), do: map

  defp maybe_put_present(map, input, key, output_key) do
    atom_key? = Map.has_key?(input, key)
    string_key = Atom.to_string(key)
    string_key? = Map.has_key?(input, string_key)

    cond do
      atom_key? ->
        Map.put(map, output_key, Map.get(input, key))

      string_key? ->
        Map.put(map, output_key, Map.get(input, string_key))

      true ->
        map
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp normalize_runtime_opts(opts) when is_list(opts), do: opts
  defp normalize_runtime_opts(opts) when is_map(opts), do: Enum.into(opts, [])
  defp normalize_runtime_opts(_opts), do: []
end
