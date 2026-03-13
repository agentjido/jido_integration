defmodule Jido.Integration.V2.Connectors.GitHubTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.DirectRuntime

  @github_capabilities [
    %{
      capability_id: "github.comment.create",
      allowed_tools: ["github.api.comment.create"],
      event_type: "connector.github.comment.created",
      artifact_key: "github/run-github-test/run-github-test:1/comment_create.term",
      input: %{
        repo: "agentjido/jido_integration_v2",
        issue_number: 42,
        body: "Add a deterministic review note"
      }
    },
    %{
      capability_id: "github.comment.update",
      allowed_tools: ["github.api.comment.update"],
      event_type: "connector.github.comment.updated",
      artifact_key: "github/run-github-test/run-github-test:1/comment_update.term",
      input: %{
        repo: "agentjido/jido_integration_v2",
        comment_id: 901,
        body: "Edited deterministic review note"
      }
    },
    %{
      capability_id: "github.issue.close",
      allowed_tools: ["github.api.issue.close"],
      event_type: "connector.github.issue.closed",
      artifact_key: "github/run-github-test/run-github-test:1/issue_close.term",
      input: %{repo: "agentjido/jido_integration_v2", issue_number: 42}
    },
    %{
      capability_id: "github.issue.create",
      allowed_tools: ["github.api.issue.create"],
      event_type: "connector.github.issue.created",
      artifact_key: "github/run-github-test/run-github-test:1/issue_create.term",
      input: %{
        repo: "agentjido/jido_integration_v2",
        title: "Ship the platform package",
        body: "Direct runtime slice"
      }
    },
    %{
      capability_id: "github.issue.fetch",
      allowed_tools: ["github.api.issue.fetch"],
      event_type: "connector.github.issue.fetched",
      artifact_key: "github/run-github-test/run-github-test:1/issue_fetch.term",
      input: %{repo: "agentjido/jido_integration_v2", issue_number: 42}
    },
    %{
      capability_id: "github.issue.label",
      allowed_tools: ["github.api.issue.label"],
      event_type: "connector.github.issue.labeled",
      artifact_key: "github/run-github-test/run-github-test:1/issue_label.term",
      input: %{
        repo: "agentjido/jido_integration_v2",
        issue_number: 42,
        labels: ["platform", "triaged"]
      }
    },
    %{
      capability_id: "github.issue.list",
      allowed_tools: ["github.api.issue.list"],
      event_type: "connector.github.issue.listed",
      artifact_key: "github/run-github-test/run-github-test:1/issue_list.term",
      input: %{repo: "agentjido/jido_integration_v2", state: "open", per_page: 2, page: 1}
    },
    %{
      capability_id: "github.issue.update",
      allowed_tools: ["github.api.issue.update"],
      event_type: "connector.github.issue.updated",
      artifact_key: "github/run-github-test/run-github-test:1/issue_update.term",
      input: %{
        repo: "agentjido/jido_integration_v2",
        issue_number: 42,
        title: "Ship the platform package now",
        body: "Expanded deterministic review surface",
        state: "open",
        labels: ["platform", "v2"],
        assignees: ["octocat"]
      }
    }
  ]

  @subject "octocat"
  @run_id "run-github-test"
  @attempt_id "#{@run_id}:1"
  @credential_ref_id "cred-github-test"
  @lease_id "lease-github-test"
  @access_token "gho_test"

  test "publishes the deterministic GitHub direct capability surface" do
    manifest = GitHub.manifest()

    assert manifest.connector == "github"

    assert Enum.map(manifest.capabilities, & &1.id) ==
             Enum.map(@github_capabilities, & &1.capability_id)

    Enum.each(@github_capabilities, fn spec ->
      capability = fetch_capability!(manifest, spec.capability_id)

      assert capability.runtime_class == :direct
      assert capability.metadata.required_scopes == ["repo"]
      assert capability.metadata.policy.environment.allowed == [:prod, :staging]
      assert capability.metadata.policy.sandbox.level == :standard
      assert capability.metadata.policy.sandbox.egress == :restricted
      assert capability.metadata.policy.sandbox.approvals == :auto
      assert capability.metadata.policy.sandbox.allowed_tools == spec.allowed_tools
    end)
  end

  for spec <- @github_capabilities do
    test "#{spec.capability_id} executes deterministically through the direct runtime" do
      spec = unquote(Macro.escape(spec))
      capability = fetch_capability!(GitHub.manifest(), spec.capability_id)

      assert {:ok, first_result} = execute(capability, spec.input)
      assert {:ok, second_result} = execute(capability, spec.input)

      assert runtime_summary(first_result) == runtime_summary(second_result)

      assert Enum.map(first_result.events, & &1.type) == [
               "attempt.started",
               spec.event_type,
               "attempt.completed"
             ]

      assert [artifact] = first_result.artifacts
      assert artifact.artifact_type == :tool_output
      assert artifact.payload_ref.store == "connector_review"
      assert artifact.payload_ref.key == spec.artifact_key
      assert artifact.metadata.connector == "github"
      assert artifact.metadata.capability_id == spec.capability_id
      assert artifact.metadata.auth_binding == first_result.output.auth_binding
      assert first_result.output.auth_binding =~ "sha256:"

      assert_output(spec.capability_id, spec.input, first_result.output)

      refute inspect(%{
               output: first_result.output,
               events: first_result.events,
               artifact: artifact
             }) =~ @access_token
    end
  end

  defp execute(capability, input) do
    DirectRuntime.execute(capability, input, execution_context(capability))
  end

  defp execution_context(capability) do
    %{
      run_id: @run_id,
      attempt_id: @attempt_id,
      credential_ref:
        CredentialRef.new!(%{
          id: @credential_ref_id,
          subject: @subject,
          scopes: ["repo"]
        }),
      credential_lease:
        CredentialLease.new!(%{
          lease_id: @lease_id,
          credential_ref_id: @credential_ref_id,
          subject: @subject,
          scopes: ["repo"],
          payload: %{access_token: @access_token},
          issued_at: ~U[2026-03-12 00:00:00Z],
          expires_at: ~U[2026-03-12 00:05:00Z]
        }),
      policy_inputs: %{
        execution: %{
          runtime_class: :direct,
          sandbox: capability.metadata.policy.sandbox
        }
      }
    }
  end

  defp fetch_capability!(manifest, capability_id) do
    Enum.find(manifest.capabilities, &(&1.id == capability_id)) ||
      raise "missing capability #{capability_id}"
  end

  defp runtime_summary(result) do
    %{
      output: result.output,
      events: result.events,
      artifacts:
        Enum.map(result.artifacts, fn artifact ->
          %{
            artifact_type: artifact.artifact_type,
            key: artifact.payload_ref.key,
            checksum: artifact.checksum,
            size_bytes: artifact.size_bytes,
            metadata: artifact.metadata
          }
        end)
    }
  end

  defp assert_output("github.issue.list", input, output) do
    issues = output.issues

    assert output.repo == input.repo
    assert output.state == input.state
    assert output.page == input.page
    assert output.per_page == input.per_page
    assert output.total_count == length(issues)
    assert length(issues) == input.per_page
    assert output.listed_by == @subject

    Enum.each(issues, fn issue ->
      assert issue.repo == input.repo
      assert issue.state == input.state
      assert is_integer(issue.issue_number)
      assert is_binary(issue.title)
      assert is_list(issue.labels)
    end)
  end

  defp assert_output("github.issue.fetch", input, output) do
    assert output.repo == input.repo
    assert output.issue_number == input.issue_number
    assert output.fetched_by == @subject
    assert is_binary(output.title)
    assert is_binary(output.body)
    assert output.state in ["open", "closed"]
    assert is_list(output.labels)
  end

  defp assert_output("github.issue.create", input, output) do
    assert output.repo == input.repo
    assert output.title == input.title
    assert output.body == input.body
    assert output.state == "open"
    assert output.labels == []
    assert output.assignees == []
    assert output.opened_by == @subject
    assert is_integer(output.issue_number)
  end

  defp assert_output("github.issue.update", input, output) do
    assert output.repo == input.repo
    assert output.issue_number == input.issue_number
    assert output.title == input.title
    assert output.body == input.body
    assert output.state == input.state
    assert output.labels == input.labels
    assert output.assignees == input.assignees
    assert output.updated_by == @subject
  end

  defp assert_output("github.issue.label", input, output) do
    assert output.repo == input.repo
    assert output.issue_number == input.issue_number
    assert output.labels == input.labels
    assert output.labeled_by == @subject
  end

  defp assert_output("github.issue.close", input, output) do
    assert output.repo == input.repo
    assert output.issue_number == input.issue_number
    assert output.state == "closed"
    assert output.closed_by == @subject
  end

  defp assert_output("github.comment.create", input, output) do
    assert output.repo == input.repo
    assert output.issue_number == input.issue_number
    assert output.body == input.body
    assert output.created_by == @subject
    assert is_integer(output.comment_id)
  end

  defp assert_output("github.comment.update", input, output) do
    assert output.repo == input.repo
    assert output.comment_id == input.comment_id
    assert output.body == input.body
    assert output.updated_by == @subject
  end
end
