defmodule Jido.Integration.Examples.GitHubAuthLifecycleTest do
  use ExUnit.Case

  @moduletag :live
  @moduletag :tmp_dir

  alias Jido.Integration.Auth.Server
  alias Jido.Integration.Examples.GitHubAuthLifecycle

  setup_all do
    token =
      try do
        GitHubAuthLifecycle.resolve_token!()
      rescue
        _ -> nil
      end

    if is_nil(token) do
      IO.puts("\n  Skipping live auth lifecycle tests — no token available.")
      IO.puts("  Run `gh auth login` or set GITHUB_TOKEN to enable.\n")
      :skip
    else
      %{token: token}
    end
  end

  setup %{token: _token} do
    {:ok, auth} = Server.start_link(name: :"gh_auth_live_#{System.unique_integer([:positive])}")
    %{auth: auth}
  end

  test "full OAuth lifecycle runs end-to-end with real token", %{auth: auth} do
    result = GitHubAuthLifecycle.run(auth)

    assert is_binary(result.connection_id)
    assert result.connection_state == :connected
    assert result.auth_ref == "auth:github:#{result.connection_id}"
    assert result.resolved_token_type == :oauth2
    assert result.manifest_id == "github"
    assert result.scopes == ["repo", "read:org"]
    assert result.connection_revision == 2
    assert result.audit_trail_length == 2
  end

  test "token refresh demo works with real token", %{auth: auth} do
    result = GitHubAuthLifecycle.demo_refresh(auth)

    assert result.original_token == "expired_placeholder"
    assert result.refresh_worked == true
    assert %DateTime{} = result.new_expiry
  end

  test "callback recovery survives Auth.Server restart and rejects duplicates", %{
    tmp_dir: tmp_dir
  } do
    result = GitHubAuthLifecycle.demo_restart_recovery(tmp_dir)

    assert result.connection_state == :connected
    assert result.callback_recovered_after_restart == true
    assert result.auth_ref == "auth:github:#{result.connection_id}"
    assert result.duplicate_callback_result == {:error, :invalid_state_token}
    assert result.audit_trail_length == 2
  end

  test "refresh failure demo transitions to reauth_required", %{auth: auth} do
    result = GitHubAuthLifecycle.demo_refresh_failure(auth)

    assert result.connection_state == :reauth_required
    assert result.requires_reauth == true
    assert length(result.audit_trail) == 3
    assert List.last(result.audit_trail) =~ "reauth_required"
  end
end
