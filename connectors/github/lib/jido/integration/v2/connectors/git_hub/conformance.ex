defmodule Jido.Integration.V2.Connectors.GitHub.Conformance do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder

  @repo "acme/platform"
  @subject "octo-user"
  @lease_payload %{access_token: "gho-demo-conformance"}
  @run_id "run-github-conformance"
  @attempt_id "run-github-conformance:1"

  @spec fixtures() :: [map()]
  def fixtures do
    auth_binding = ArtifactBuilder.digest(@lease_payload.access_token)

    [
      %{
        capability_id: "github.issue.list",
        input: %{repo: @repo, state: "open", per_page: 2, page: 1},
        credential_ref: credential_ref(),
        credential_lease: credential_lease(),
        context: %{run_id: @run_id, attempt_id: @attempt_id},
        expect: %{
          output: %{
            repo: @repo,
            state: "open",
            page: 1,
            per_page: 2,
            total_count: 2,
            issues: [
              deterministic_issue(@repo, "open", 1, 0),
              deterministic_issue(@repo, "open", 1, 1)
            ],
            listed_by: @subject,
            auth_binding: auth_binding
          },
          event_types: [
            "attempt.started",
            "connector.github.issue.listed",
            "attempt.completed"
          ],
          artifact_types: [:tool_output],
          artifact_keys: ["github/#{@run_id}/#{@attempt_id}/issue_list.term"]
        }
      },
      %{
        capability_id: "github.issue.fetch",
        input: %{repo: @repo, issue_number: 77},
        credential_ref: credential_ref(),
        credential_lease: credential_lease(),
        context: %{run_id: @run_id, attempt_id: @attempt_id},
        expect: %{
          output: %{
            repo: @repo,
            issue_number: 77,
            title: "Issue 77 in #{@repo}",
            body: "Deterministic issue payload for #{@repo}#77",
            state: "closed",
            labels: ["enhancement"],
            fetched_by: @subject,
            auth_binding: auth_binding
          },
          event_types: [
            "attempt.started",
            "connector.github.issue.fetched",
            "attempt.completed"
          ],
          artifact_types: [:tool_output],
          artifact_keys: ["github/#{@run_id}/#{@attempt_id}/issue_fetch.term"]
        }
      },
      %{
        capability_id: "github.issue.create",
        input: %{
          repo: @repo,
          title: "Conformance review",
          body: "Generated from deterministic fixture"
        },
        credential_ref: credential_ref(),
        credential_lease: credential_lease(),
        context: %{run_id: @run_id, attempt_id: @attempt_id},
        expect: %{
          output: %{
            repo: @repo,
            issue_number: :erlang.phash2({@repo, "Conformance review", @subject}, 10_000),
            title: "Conformance review",
            body: "Generated from deterministic fixture",
            state: "open",
            labels: [],
            assignees: [],
            opened_by: @subject,
            auth_binding: auth_binding
          },
          event_types: [
            "attempt.started",
            "connector.github.issue.created",
            "attempt.completed"
          ],
          artifact_types: [:tool_output],
          artifact_keys: ["github/#{@run_id}/#{@attempt_id}/issue_create.term"]
        }
      },
      %{
        capability_id: "github.issue.update",
        input: %{
          repo: @repo,
          issue_number: 77,
          title: "Conformance review updated",
          body: "Expanded deterministic coverage",
          state: "open",
          labels: ["platform", "v2"],
          assignees: ["octo-user"]
        },
        credential_ref: credential_ref(),
        credential_lease: credential_lease(),
        context: %{run_id: @run_id, attempt_id: @attempt_id},
        expect: %{
          output: %{
            repo: @repo,
            issue_number: 77,
            title: "Conformance review updated",
            body: "Expanded deterministic coverage",
            state: "open",
            labels: ["platform", "v2"],
            assignees: ["octo-user"],
            updated_by: @subject,
            auth_binding: auth_binding
          },
          event_types: [
            "attempt.started",
            "connector.github.issue.updated",
            "attempt.completed"
          ],
          artifact_types: [:tool_output],
          artifact_keys: ["github/#{@run_id}/#{@attempt_id}/issue_update.term"]
        }
      },
      %{
        capability_id: "github.issue.label",
        input: %{repo: @repo, issue_number: 77, labels: ["platform", "triaged"]},
        credential_ref: credential_ref(),
        credential_lease: credential_lease(),
        context: %{run_id: @run_id, attempt_id: @attempt_id},
        expect: %{
          output: %{
            repo: @repo,
            issue_number: 77,
            labels: ["platform", "triaged"],
            labeled_by: @subject,
            auth_binding: auth_binding
          },
          event_types: [
            "attempt.started",
            "connector.github.issue.labeled",
            "attempt.completed"
          ],
          artifact_types: [:tool_output],
          artifact_keys: ["github/#{@run_id}/#{@attempt_id}/issue_label.term"]
        }
      },
      %{
        capability_id: "github.issue.close",
        input: %{repo: @repo, issue_number: 77},
        credential_ref: credential_ref(),
        credential_lease: credential_lease(),
        context: %{run_id: @run_id, attempt_id: @attempt_id},
        expect: %{
          output: %{
            repo: @repo,
            issue_number: 77,
            state: "closed",
            closed_by: @subject,
            auth_binding: auth_binding
          },
          event_types: [
            "attempt.started",
            "connector.github.issue.closed",
            "attempt.completed"
          ],
          artifact_types: [:tool_output],
          artifact_keys: ["github/#{@run_id}/#{@attempt_id}/issue_close.term"]
        }
      },
      %{
        capability_id: "github.comment.create",
        input: %{repo: @repo, issue_number: 77, body: "Generated comment"},
        credential_ref: credential_ref(),
        credential_lease: credential_lease(),
        context: %{run_id: @run_id, attempt_id: @attempt_id},
        expect: %{
          output: %{
            repo: @repo,
            issue_number: 77,
            comment_id: :erlang.phash2({@repo, 77, "Generated comment", @subject}, 100_000),
            body: "Generated comment",
            created_by: @subject,
            auth_binding: auth_binding
          },
          event_types: [
            "attempt.started",
            "connector.github.comment.created",
            "attempt.completed"
          ],
          artifact_types: [:tool_output],
          artifact_keys: ["github/#{@run_id}/#{@attempt_id}/comment_create.term"]
        }
      },
      %{
        capability_id: "github.comment.update",
        input: %{repo: @repo, comment_id: 901, body: "Updated comment"},
        credential_ref: credential_ref(),
        credential_lease: credential_lease(),
        context: %{run_id: @run_id, attempt_id: @attempt_id},
        expect: %{
          output: %{
            repo: @repo,
            comment_id: 901,
            body: "Updated comment",
            updated_by: @subject,
            auth_binding: auth_binding
          },
          event_types: [
            "attempt.started",
            "connector.github.comment.updated",
            "attempt.completed"
          ],
          artifact_types: [:tool_output],
          artifact_keys: ["github/#{@run_id}/#{@attempt_id}/comment_update.term"]
        }
      }
    ]
  end

  defp credential_ref do
    %{
      id: "cred-github-conformance",
      subject: @subject,
      scopes: ["repo"]
    }
  end

  defp credential_lease do
    %{
      lease_id: "lease-github-conformance",
      credential_ref_id: "cred-github-conformance",
      subject: @subject,
      scopes: ["repo"],
      payload: @lease_payload,
      issued_at: ~U[2026-03-12 00:00:00Z],
      expires_at: ~U[2026-03-12 00:05:00Z]
    }
  end

  defp deterministic_issue(repo, state, page, offset) do
    issue_number = :erlang.phash2({repo, state, page, offset}, 90_000) + 1

    %{
      repo: repo,
      issue_number: issue_number,
      title: "Deterministic #{state} issue #{issue_number}",
      state: state,
      labels: label_set(issue_number)
    }
  end

  defp label_set(issue_number) when rem(issue_number, 2) == 0, do: ["bug", "triaged"]
  defp label_set(_issue_number), do: ["enhancement"]
end
