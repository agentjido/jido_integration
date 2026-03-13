defmodule Jido.Integration.Examples.GitHubIntegrationTest do
  use ExUnit.Case

  @moduletag :live

  alias Jido.Integration.Connectors.GitHub
  alias Jido.Integration.Examples.GitHubIntegration

  setup_all do
    # Ensure real HTTP client
    Application.put_env(:jido_integration_github, GitHub,
      http_client: Jido.Integration.Connectors.GitHub.DefaultClient
    )

    token =
      try do
        GitHubIntegration.resolve_token!()
      rescue
        _ -> nil
      end

    if is_nil(token) do
      IO.puts("\n  Skipping live GitHub tests — no token available.")
      IO.puts("  Run `gh auth login` or set GITHUB_TOKEN to enable.\n")
      :skip
    else
      %{token: token}
    end
  end

  setup %{token: _token} do
    infra = GitHubIntegration.setup_infrastructure()
    %{infra: infra}
  end

  describe "OAuth install flow" do
    test "install -> callback -> connected with real token", %{infra: infra} do
      result = GitHubIntegration.install_github(infra)

      assert result.connection_state == :connected
      assert result.auth_ref == "auth:github:#{result.connection_id}"
      assert is_binary(result.connection_id)
      assert is_binary(result.auth_url)
      assert result.scopes == ["repo", "read:org"]
      assert result.revision == 2
      assert result.audit_trail_length == 2
    end
  end

  describe "live API operations" do
    setup %{infra: infra} do
      install = GitHubIntegration.install_github(infra)
      %{install: install}
    end

    test "list_issues returns real issues from elixir-lang/elixir", %{
      infra: infra,
      install: install
    } do
      {:ok, result} = GitHubIntegration.list_issues(infra, install)

      assert result.status == :ok
      assert is_list(result.result["issues"])
      assert result.result["total_count"] > 0

      first_issue = hd(result.result["issues"])
      assert is_integer(first_issue["number"])
      assert is_binary(first_issue["title"])
    end
  end

  describe "scope enforcement" do
    test "missing 'repo' scope blocks operation", %{infra: infra} do
      result = GitHubIntegration.test_scope_enforcement(infra)

      assert result.error_class == :auth_failed
      assert result.error_code == "auth.missing_scopes"
      assert result.error_message =~ "repo"
    end
  end

  describe "blocked connection state" do
    test "reauth_required state blocks execution", %{infra: infra} do
      install = GitHubIntegration.install_github(infra)
      result = GitHubIntegration.test_blocked_state(infra, install)

      assert result.error_class == :auth_failed
      assert result.error_code == "auth.connection_blocked"
      assert result.blocked_state == "reauth_required"
    end
  end

  describe "webhook ingress pipeline" do
    test "route -> verify -> dedupe -> dispatch", %{infra: infra} do
      result = GitHubIntegration.webhook_ingress(infra)

      assert is_map(result.issue_event)
      assert result.issue_event["event_type"] == "issues"
      assert result.duplicate_rejected == true
      assert result.signature_rejected == true
      assert result.unknown_route_rejected == true
      assert result.routes_registered >= 1
    end
  end

  describe "token refresh" do
    test "expired credential is transparently refreshed to real token", %{infra: infra} do
      result = GitHubIntegration.token_refresh(infra)

      assert result.original_token == "expired_placeholder"
      assert result.refresh_worked == true
      assert %DateTime{} = result.new_expiry
    end
  end

  describe "refresh failure" do
    test "terminal refresh failure transitions connection to reauth_required", %{infra: infra} do
      result = GitHubIntegration.refresh_failure(infra)

      assert result.connection_state == :reauth_required
      assert result.requires_reauth == true
      assert length(result.audit_trail) == 3
      assert List.last(result.audit_trail) =~ "reauth_required"
      assert List.last(result.audit_trail) =~ "system:refresh_failed"
    end
  end

  describe "credential rotation" do
    test "rotate replaces the stored token with real token", %{infra: infra} do
      result = GitHubIntegration.credential_rotation(infra)

      assert result.old_token == "old_token_to_rotate"
      assert result.rotation_worked == true
    end
  end

  describe "credential revocation" do
    test "revoke removes credential, resolve fails after", %{infra: infra} do
      result = GitHubIntegration.credential_revocation(infra)

      assert result.revoke_ok == true
      assert {:error, :not_found} = result.resolve_after_revoke
    end
  end

  describe "connection degradation" do
    test "mark_rotation_overdue -> degraded, then recover -> connected", %{infra: infra} do
      result = GitHubIntegration.connection_degradation(infra)

      assert result.degraded_state == :degraded
      assert result.recovered_state == :connected
      assert result.degradation_worked == true
      assert result.recovery_worked == true
    end
  end

  describe "connection lifecycle" do
    test "full lifecycle: connected -> degraded -> reauth_required -> reinstall -> connected", %{
      infra: infra
    } do
      result = GitHubIntegration.connection_lifecycle(infra)

      assert result.initial_state == :connected
      assert result.degraded_state == :degraded
      assert result.reauth_state == :reauth_required
      assert result.reinstalling_state == :installing
      assert result.reconnected_state == :connected
      assert result.final_revision == 6
      assert length(result.audit_trail) == 6
    end
  end

  describe "write operations" do
    @describetag :live_write

    setup %{infra: infra} do
      try do
        {owner, repo} = GitHubIntegration.resolve_write_repo!()
        install = GitHubIntegration.install_github(infra, "write-test")
        %{install: install, owner: owner, repo: repo}
      rescue
        _ ->
          IO.puts("  Skipping write tests — set GITHUB_TEST_OWNER and GITHUB_TEST_REPO")
          :skip
      end
    end

    test "create, fetch, update, label, comment, and close on real repo", %{
      infra: infra,
      install: install,
      owner: owner,
      repo: repo
    } do
      {:ok, issue} = GitHubIntegration.create_issue(infra, install, owner, repo)
      issue_number = issue.result["number"]
      updated_title = issue.result["title"] <> " [updated]"

      assert issue.status == :ok
      assert is_integer(issue_number)
      assert issue.result["html_url"] =~ "github.com"

      {:ok, fetched} = GitHubIntegration.fetch_issue(infra, install, owner, repo, issue_number)
      assert fetched.status == :ok
      assert fetched.result["number"] == issue_number

      {:ok, labeled} =
        GitHubIntegration.label_issue(infra, install, owner, repo, issue_number, [
          "jido-integration"
        ])

      assert labeled.status == :ok
      assert Enum.any?(labeled.result["labels"], &(&1["name"] == "jido-integration"))

      {:ok, updated_issue} =
        GitHubIntegration.update_issue(infra, install, owner, repo, issue_number, %{
          "title" => updated_title
        })

      assert updated_issue.status == :ok
      assert updated_issue.result["number"] == issue_number
      assert updated_issue.result["title"] == updated_title

      {:ok, comment} = GitHubIntegration.create_comment(infra, install, owner, repo, issue_number)

      assert comment.status == :ok
      assert is_integer(comment.result["id"])

      {:ok, updated_comment} =
        GitHubIntegration.update_comment(
          infra,
          install,
          owner,
          repo,
          comment.result["id"],
          "Updated by the GitHub live acceptance test."
        )

      assert updated_comment.status == :ok
      assert updated_comment.result["id"] == comment.result["id"]
      assert updated_comment.result["body"] == "Updated by the GitHub live acceptance test."

      {:ok, closed} = GitHubIntegration.close_issue(infra, install, owner, repo, issue_number)
      assert closed.status == :ok
      assert closed.result["state"] == "closed"
    end
  end

  describe "run_read_only/0" do
    test "full read-only demo runs end-to-end against live GitHub API" do
      result = GitHubIntegration.run_read_only()

      assert result.install.connection_state == :connected
      assert result.list_issues.status == :ok
      assert result.list_issues.result["total_count"] > 0
      assert result.scope_enforcement.error_class == :auth_failed
      assert result.blocked_state.error_class == :auth_failed
      assert result.webhook.duplicate_rejected == true
      assert result.token_refresh.refresh_worked == true
      assert result.refresh_failure.requires_reauth == true
      assert result.credential_rotation.rotation_worked == true
      assert result.credential_revocation.revoke_ok == true
      assert result.connection_degradation.degradation_worked == true
      assert result.connection_lifecycle.reconnected_state == :connected
    end
  end
end
