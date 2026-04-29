defmodule Jido.Integration.V2.Connectors.Linear.Fixtures do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef

  @run_id "run-linear-test"
  @attempt_id "#{@run_id}:1"
  @subject "usr-linear-viewer"
  @credential_ref_id "cred-linear-test"
  @lease_id "lease-linear-test"
  @profile_id "api_key_user"
  @api_key "lin_api_test_secret"
  @oauth_access_token "lin_oauth_test_secret"
  @auth_binding ArtifactBuilder.digest(@api_key)
  @issue_id "lin-issue-321"
  @issue_identifier "ENG-321"
  @state_backlog %{id: "state-backlog", name: "Backlog", type: "unstarted"}
  @state_in_progress %{id: "state-in-progress", name: "In Progress", type: "started"}
  @viewer %{id: @subject, name: "Taylor Automation", email: "taylor@example.test"}
  @project %{
    id: "project-ops",
    name: "Ops Automation",
    slug_id: "ops-automation",
    url: "https://linear.app/acme/project/ops-automation"
  }
  @team %{id: "team-eng", key: "ENG", name: "Engineering"}
  @issue_summary %{
    id: @issue_id,
    identifier: @issue_identifier,
    title: "Investigate deployment rollback",
    priority: 2,
    branch_name: "eng-321-investigate-rollback",
    labels: ["incident", "automation"],
    url: "https://linear.app/acme/issue/#{@issue_identifier}",
    created_at: "2026-03-12T09:15:00Z",
    updated_at: "2026-03-12T10:00:00Z",
    state: @state_backlog,
    assignee: @viewer,
    project: @project,
    team: @team
  }
  @second_issue_summary %{
    id: "lin-issue-654",
    identifier: "ENG-654",
    title: "Audit release checklist",
    priority: 3,
    branch_name: "eng-654-audit-release-checklist",
    labels: ["release"],
    url: "https://linear.app/acme/issue/ENG-654",
    created_at: "2026-03-12T08:00:00Z",
    updated_at: "2026-03-12T09:45:00Z",
    state: @state_in_progress,
    assignee: @viewer,
    project: @project,
    team: @team
  }
  @issue_detail Map.merge(@issue_summary, %{
                  description: "The deployment rolled back after the health checks failed.",
                  branch_name: "eng-321-investigate-rollback",
                  labels: ["incident", "automation"],
                  blockers: [
                    %{
                      id: "rel-blocks-001",
                      type: "blocks",
                      direction: "inbound",
                      issue: %{
                        id: "lin-issue-009",
                        identifier: "SEC-9",
                        title: "Restore deployment credentials",
                        url: "https://linear.app/acme/issue/SEC-9",
                        state: @state_in_progress
                      }
                    }
                  ],
                  team: Map.put(@team, :workflow_states, [@state_backlog, @state_in_progress])
                })
  @updated_issue %{
    id: @issue_id,
    identifier: @issue_identifier,
    title: "Investigate deployment rollback now",
    url: "https://linear.app/acme/issue/#{@issue_identifier}",
    updated_at: "2026-03-12T11:00:00Z",
    state: @state_in_progress
  }
  @created_comment %{
    id: "comment-linear-555",
    body: "Handing this back to the queue.",
    issue: %{id: @issue_id, identifier: @issue_identifier}
  }
  @updated_comment %{
    id: "comment-linear-workpad",
    body: "Updated workpad progress.",
    issue: %{id: @issue_id, identifier: @issue_identifier}
  }

  @capability_specs [
    %{
      capability_id: "linear.comments.create",
      event_type: "connector.linear.comments.create.completed",
      artifact_key: "linear/#{@run_id}/#{@attempt_id}/comments_create.term",
      input: %{issue_id: @issue_id, body: "Handing this back to the queue."},
      output: %{success: true, comment: @created_comment, auth_binding: @auth_binding}
    },
    %{
      capability_id: "linear.comments.update",
      event_type: "connector.linear.comments.update.completed",
      artifact_key: "linear/#{@run_id}/#{@attempt_id}/comments_update.term",
      input: %{comment_id: @updated_comment.id, body: @updated_comment.body},
      output: %{success: true, comment: @updated_comment, auth_binding: @auth_binding}
    },
    %{
      capability_id: "linear.graphql.execute",
      event_type: "connector.linear.graphql.execute.completed",
      artifact_key: "linear/#{@run_id}/#{@attempt_id}/graphql_execute.term",
      input: %{
        query:
          "query JidoLinearRawViewer($includeEmail: Boolean!) { viewer { id name email @include(if: $includeEmail) } }",
        variables: %{"includeEmail" => false},
        operation_name: "JidoLinearRawViewer"
      },
      output: %{
        data: %{"viewer" => %{"id" => @subject, "name" => @viewer.name}},
        auth_binding: @auth_binding
      }
    },
    %{
      capability_id: "linear.issues.list",
      event_type: "connector.linear.issues.list.completed",
      artifact_key: "linear/#{@run_id}/#{@attempt_id}/issues_list.term",
      input: %{
        filter: %{
          project_slug: "ops-automation",
          state_names: ["Backlog", "In Progress"],
          assignee_id: @subject
        },
        first: 2
      },
      output: %{
        issues: [@issue_summary, @second_issue_summary],
        page_info: %{has_next_page: false, end_cursor: "cursor-issue-654"},
        auth_binding: @auth_binding
      }
    },
    %{
      capability_id: "linear.issues.retrieve",
      event_type: "connector.linear.issues.retrieve.completed",
      artifact_key: "linear/#{@run_id}/#{@attempt_id}/issues_retrieve.term",
      input: %{issue_id: @issue_id},
      output: %{issue: @issue_detail, auth_binding: @auth_binding}
    },
    %{
      capability_id: "linear.issues.update",
      event_type: "connector.linear.issues.update.completed",
      artifact_key: "linear/#{@run_id}/#{@attempt_id}/issues_update.term",
      input: %{
        issue_id: @issue_id,
        state_id: @state_in_progress.id,
        title: @updated_issue.title
      },
      output: %{success: true, issue: @updated_issue, auth_binding: @auth_binding}
    },
    %{
      capability_id: "linear.users.get_self",
      event_type: "connector.linear.users.get_self.completed",
      artifact_key: "linear/#{@run_id}/#{@attempt_id}/users_get_self.term",
      input: %{},
      output: %{user: @viewer, auth_binding: @auth_binding}
    },
    %{
      capability_id: "linear.workflow_states.list",
      event_type: "connector.linear.workflow_states.list.completed",
      artifact_key: "linear/#{@run_id}/#{@attempt_id}/workflow_states_list.term",
      input: %{
        filter: %{
          state_ids: [@state_backlog.id, @state_in_progress.id],
          team_id: @team.id
        },
        first: 10
      },
      output: %{
        workflow_states: [
          Map.put(@state_backlog, :team, @team),
          Map.put(@state_in_progress, :team, @team)
        ],
        page_info: %{has_next_page: false, end_cursor: "cursor-state-in-progress"},
        auth_binding: @auth_binding
      }
    }
  ]

  @spec specs() :: [map()]
  def specs, do: Enum.sort_by(@capability_specs, & &1.capability_id)

  @spec published_capability_ids() :: [String.t()]
  def published_capability_ids do
    specs()
    |> Enum.map(& &1.capability_id)
  end

  @spec api_key() :: String.t()
  def api_key, do: @api_key

  @spec oauth_access_token() :: String.t()
  def oauth_access_token, do: @oauth_access_token

  @spec auth_binding(String.t()) :: String.t()
  def auth_binding(secret \\ @api_key), do: ArtifactBuilder.digest(secret)

  @spec credential_ref() :: CredentialRef.t()
  def credential_ref do
    CredentialRef.new!(credential_ref_attrs())
  end

  @spec credential_ref_attrs() :: map()
  def credential_ref_attrs do
    %{
      id: @credential_ref_id,
      profile_id: @profile_id,
      subject: @subject,
      scopes: ["read", "write"],
      lease_fields: ["api_key"]
    }
  end

  @spec credential_lease() :: CredentialLease.t()
  def credential_lease do
    CredentialLease.new!(credential_lease_attrs())
  end

  @spec credential_lease_attrs() :: map()
  def credential_lease_attrs do
    %{
      lease_id: @lease_id,
      tenant_id: "tenant-linear-fixture",
      credential_ref_id: @credential_ref_id,
      profile_id: @profile_id,
      subject: @subject,
      scopes: ["read", "write"],
      payload: %{api_key: @api_key},
      lease_fields: ["api_key"],
      issued_at: ~U[2026-03-12 00:00:00Z],
      expires_at: ~U[2026-03-12 00:05:00Z]
    }
  end

  @spec oauth_credential_lease() :: CredentialLease.t()
  def oauth_credential_lease do
    CredentialLease.new!(%{
      lease_id: "lease-linear-oauth-test",
      tenant_id: "tenant-linear-fixture",
      credential_ref_id: @credential_ref_id,
      profile_id: "oauth_user",
      subject: @subject,
      scopes: ["read", "write"],
      payload: %{access_token: @oauth_access_token},
      lease_fields: ["access_token"],
      issued_at: ~U[2026-03-12 00:00:00Z],
      expires_at: ~U[2026-03-12 00:05:00Z]
    })
  end

  @spec client_opts() :: keyword()
  def client_opts do
    [transport: Jido.Integration.V2.Connectors.Linear.FixtureTransport]
  end

  @spec request_opts(pid() | nil, keyword()) :: keyword()
  def request_opts(test_pid, opts \\ []) do
    []
    |> maybe_put(:test_pid, test_pid)
    |> maybe_put(:response, Keyword.get(opts, :response))
  end

  @spec execution_context(String.t(), keyword()) :: map()
  def execution_context(_capability_id, opts \\ []) do
    %{
      run_id: @run_id,
      attempt_id: @attempt_id,
      credential_ref: credential_ref(),
      credential_lease: credential_lease(),
      policy_inputs: %{
        execution: %{
          runtime_class: :direct,
          sandbox: %{
            level: :standard,
            egress: :restricted,
            approvals: :auto,
            allowed_tools: []
          }
        }
      },
      opts: %{
        linear_client: Keyword.get(opts, :linear_client, client_opts()),
        linear_request: Keyword.get(opts, :linear_request, request_opts(nil))
      }
    }
  end

  @spec input_for(String.t()) :: map()
  def input_for(capability_id) do
    specs()
    |> Enum.find(&(&1.capability_id == capability_id))
    |> Map.fetch!(:input)
  end

  @spec expected_output(String.t()) :: map()
  def expected_output(capability_id) do
    specs()
    |> Enum.find(&(&1.capability_id == capability_id))
    |> Map.fetch!(:output)
  end

  @spec assert_request(String.t(), map(), map()) :: true
  def assert_request(capability_id, payload, context) do
    headers = Map.new(context.headers)
    input = input_for(capability_id)

    expect_equal(headers["authorization"], @api_key, "authorization header")
    expect_equal(context.base_url, "https://api.linear.app/graphql", "base url")

    case capability_id do
      "linear.users.get_self" ->
        expect_equal(payload["operationName"], "JidoLinearViewer", "operation name")
        expect_contains(payload["query"], "query JidoLinearViewer", "query document")
        expect_equal(payload["variables"], %{}, "variables")

      "linear.issues.list" ->
        expect_equal(payload["operationName"], "JidoLinearIssuesList", "operation name")
        expect_contains(payload["query"], "query JidoLinearIssuesList", "query document")

        expect_equal(
          payload["variables"],
          %{
            "filter" => %{
              "project" => %{"slugId" => %{"eq" => "ops-automation"}},
              "state" => %{"name" => %{"in" => input.filter.state_names}},
              "assignee" => %{"id" => %{"eq" => @subject}}
            },
            "first" => 2
          },
          "variables"
        )

      "linear.workflow_states.list" ->
        expect_equal(payload["operationName"], "JidoLinearWorkflowStatesList", "operation name")
        expect_contains(payload["query"], "query JidoLinearWorkflowStatesList", "query document")

        expect_equal(
          payload["variables"],
          %{
            "filter" => %{
              "id" => %{"in" => input.filter.state_ids},
              "team" => %{"id" => %{"eq" => @team.id}}
            },
            "first" => 10
          },
          "variables"
        )

      "linear.issues.retrieve" ->
        expect_equal(payload["operationName"], "JidoLinearIssueRetrieve", "operation name")
        expect_contains(payload["query"], "query JidoLinearIssueRetrieve", "query document")
        expect_equal(payload["variables"], %{"issueId" => @issue_id}, "variables")

      "linear.comments.create" ->
        expect_equal(payload["operationName"], "JidoLinearCommentCreate", "operation name")
        expect_contains(payload["query"], "mutation JidoLinearCommentCreate", "query document")

        expect_equal(
          payload["variables"],
          %{"issueId" => @issue_id, "body" => input.body},
          "variables"
        )

      "linear.comments.update" ->
        expect_equal(payload["operationName"], "JidoLinearCommentUpdate", "operation name")
        expect_contains(payload["query"], "mutation JidoLinearCommentUpdate", "query document")

        expect_equal(
          payload["variables"],
          %{"commentId" => @updated_comment.id, "body" => @updated_comment.body},
          "variables"
        )

      "linear.issues.update" ->
        expect_equal(payload["operationName"], "JidoLinearIssueUpdate", "operation name")
        expect_contains(payload["query"], "mutation JidoLinearIssueUpdate", "query document")

        expect_equal(
          payload["variables"],
          %{
            "issueId" => @issue_id,
            "input" => %{
              "stateId" => @state_in_progress.id,
              "title" => @updated_issue.title
            }
          },
          "variables"
        )

      "linear.graphql.execute" ->
        expect_equal(payload["operationName"], input.operation_name, "operation name")
        expect_equal(payload["query"], input.query, "query document")
        expect_equal(payload["variables"], input.variables, "variables")
    end

    true
  end

  @spec response_for_request(map(), map(), keyword()) :: {:ok, map()}
  def response_for_request(payload, _context, _opts \\ []) do
    operation_name = payload["operationName"]

    case response_data_for_operation(operation_name) do
      nil -> missing_fixture_response(operation_name)
      data -> sdk_response(data)
    end
  end

  @spec not_found_response() :: (map(), map(), keyword() -> {:ok, map()})
  def not_found_response do
    fn _payload, _context, _opts ->
      raw_response(
        %{
          "errors" => [
            %{
              "message" => "Issue not found",
              "extensions" => %{"code" => "NOT_FOUND"},
              "body" => %{"api_key" => @api_key}
            }
          ],
          "body" => %{"api_key" => @api_key}
        },
        200,
        [{"x-request-id", "req-linear-missing"}]
      )
    end
  end

  defp viewer_body do
    %{
      "id" => @viewer.id,
      "name" => @viewer.name,
      "email" => @viewer.email
    }
  end

  defp response_data_for_operation(operation_name) do
    Map.get(
      %{
        "JidoLinearViewer" => %{"viewer" => viewer_body()},
        "JidoLinearIssuesList" => %{"issues" => issues_connection_body()},
        "JidoLinearWorkflowStatesList" => %{"workflowStates" => workflow_states_connection_body()},
        "JidoLinearIssueRetrieve" => %{"issue" => issue_detail_body()},
        "JidoLinearCommentCreate" => %{"commentCreate" => comment_create_body()},
        "JidoLinearCommentUpdate" => %{"commentUpdate" => comment_update_body()},
        "JidoLinearIssueUpdate" => %{"issueUpdate" => issue_update_body()},
        "JidoLinearRawViewer" => %{"viewer" => %{"id" => @subject, "name" => @viewer.name}}
      },
      operation_name
    )
  end

  defp missing_fixture_response(operation_name) do
    sdk_response(
      %{
        "errors" => [
          %{"message" => "missing linear fixture for #{inspect(operation_name)}"}
        ]
      },
      500
    )
  end

  defp issues_connection_body do
    %{
      "pageInfo" => %{
        "hasNextPage" => false,
        "endCursor" => "cursor-issue-654"
      },
      "nodes" => [
        issue_summary_body(@issue_summary),
        issue_summary_body(@second_issue_summary)
      ]
    }
  end

  defp workflow_states_connection_body do
    %{
      "pageInfo" => %{
        "hasNextPage" => false,
        "endCursor" => "cursor-state-in-progress"
      },
      "nodes" => [
        workflow_state_body(Map.put(@state_backlog, :team, @team)),
        workflow_state_body(Map.put(@state_in_progress, :team, @team))
      ]
    }
  end

  defp issue_detail_body do
    base = issue_summary_body(@issue_detail)

    Map.merge(base, %{
      "description" => @issue_detail.description,
      "branchName" => @issue_detail.branch_name,
      "labels" => %{
        "nodes" => Enum.map(@issue_detail.labels, &%{"name" => &1})
      },
      "relations" => %{"nodes" => []},
      "inverseRelations" => %{
        "nodes" => [
          %{
            "id" => "rel-blocks-001",
            "type" => "blocks",
            "issue" => %{
              "id" => "lin-issue-009",
              "identifier" => "SEC-9",
              "title" => "Restore deployment credentials",
              "url" => "https://linear.app/acme/issue/SEC-9",
              "state" => workflow_state_body(@state_in_progress)
            }
          }
        ]
      },
      "team" => %{
        "id" => @team.id,
        "key" => @team.key,
        "name" => @team.name,
        "states" => %{
          "nodes" => Enum.map(@issue_detail.team.workflow_states, &workflow_state_body/1)
        }
      }
    })
  end

  defp comment_create_body do
    %{
      "success" => true,
      "comment" => %{
        "id" => @created_comment.id,
        "body" => @created_comment.body,
        "issue" => %{
          "id" => @issue_id,
          "identifier" => @issue_identifier
        }
      }
    }
  end

  defp comment_update_body do
    %{
      "success" => true,
      "comment" => %{
        "id" => @updated_comment.id,
        "body" => @updated_comment.body,
        "issue" => %{
          "id" => @issue_id,
          "identifier" => @issue_identifier
        }
      }
    }
  end

  defp issue_update_body do
    %{
      "success" => true,
      "issue" => %{
        "id" => @updated_issue.id,
        "identifier" => @updated_issue.identifier,
        "title" => @updated_issue.title,
        "url" => @updated_issue.url,
        "updatedAt" => @updated_issue.updated_at,
        "state" => workflow_state_body(@updated_issue.state)
      }
    }
  end

  defp issue_summary_body(summary) do
    %{
      "id" => summary.id,
      "identifier" => summary.identifier,
      "title" => summary.title,
      "priority" => summary.priority,
      "branchName" => summary.branch_name,
      "labels" => %{
        "nodes" => Enum.map(summary.labels, &%{"name" => &1})
      },
      "url" => summary.url,
      "createdAt" => summary.created_at,
      "updatedAt" => summary.updated_at,
      "state" => workflow_state_body(summary.state),
      "assignee" => user_body(summary.assignee),
      "project" => project_body(summary.project),
      "team" => team_body(summary.team)
    }
  end

  defp user_body(user) do
    %{
      "id" => user.id,
      "name" => user.name,
      "email" => user.email
    }
  end

  defp project_body(project) do
    %{
      "id" => project.id,
      "name" => project.name,
      "slugId" => project.slug_id,
      "url" => project.url
    }
  end

  defp team_body(team) do
    %{
      "id" => team.id,
      "key" => team.key,
      "name" => team.name
    }
  end

  defp workflow_state_body(nil), do: nil

  defp workflow_state_body(state) do
    %{
      "id" => state.id,
      "name" => state.name,
      "type" => state.type
    }
    |> maybe_put_map("team", Map.get(state, :team) && team_body(state.team))
  end

  defp sdk_response(data, status \\ 200, headers \\ [{"x-request-id", "req-linear-fixture"}]) do
    raw_response(%{"data" => data}, status, headers)
  end

  defp raw_response(body, status, headers) do
    {:ok,
     %{
       status: status,
       headers: headers,
       body: body
     }}
  end

  defp expect_equal(actual, expected, label) do
    if actual != expected do
      raise RuntimeError,
        message: "expected #{label} #{inspect(expected)}, got #{inspect(actual)}"
    end
  end

  defp expect_contains(actual, expected_fragment, label) do
    if not String.contains?(actual, expected_fragment) do
      raise RuntimeError,
        message:
          "expected #{label} to contain #{inspect(expected_fragment)}, got #{inspect(actual)}"
    end
  end

  defp maybe_put(list, _key, nil), do: list
  defp maybe_put(list, key, value), do: Keyword.put(list, key, value)

  defp maybe_put_map(map, _key, nil), do: map
  defp maybe_put_map(map, key, value), do: Map.put(map, key, value)
end
