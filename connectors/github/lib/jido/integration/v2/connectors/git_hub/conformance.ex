defmodule Jido.Integration.V2.Connectors.GitHub.Conformance do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder

  @repo "acme/platform"
  @title "Conformance review"
  @body "Generated from deterministic fixture"
  @subject "octo-user"
  @run_id "run-github-conformance"
  @attempt_id "run-github-conformance:1"
  @lease_payload %{access_token: "gho-demo-conformance"}

  @spec fixtures() :: [map()]
  def fixtures do
    auth_binding = ArtifactBuilder.digest(@lease_payload.access_token)

    [
      %{
        capability_id: "github.issue.create",
        input: %{repo: @repo, title: @title, body: @body},
        credential_ref: %{
          id: "cred-github-conformance",
          subject: @subject,
          scopes: ["repo"]
        },
        credential_lease: %{
          lease_id: "lease-github-conformance",
          credential_ref_id: "cred-github-conformance",
          subject: @subject,
          scopes: ["repo"],
          payload: @lease_payload,
          issued_at: ~U[2026-03-12 00:00:00Z],
          expires_at: ~U[2026-03-12 00:05:00Z]
        },
        context: %{
          run_id: @run_id,
          attempt_id: @attempt_id
        },
        expect: %{
          output: %{
            issue_number: :erlang.phash2({@repo, @title, @subject}, 10_000),
            repo: @repo,
            title: @title,
            body: @body,
            opened_by: @subject,
            auth_binding: auth_binding
          },
          event_types: [
            "attempt.started",
            "connector.github.issue.created",
            "attempt.completed"
          ],
          artifact_types: [:tool_output],
          artifact_keys: [
            "github/#{@run_id}/#{@attempt_id}/issue_create.term"
          ]
        }
      }
    ]
  end
end
