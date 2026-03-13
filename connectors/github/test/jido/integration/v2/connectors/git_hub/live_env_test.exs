defmodule Jido.Integration.V2.Connectors.GitHub.LiveEnvTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.GitHub.LiveEnv

  @env LiveEnv.env_names()

  test "defaults to deterministic offline mode when live env vars are absent" do
    spec = LiveEnv.spec(%{})

    refute spec.read_enabled?
    refute spec.write_enabled?
    assert spec.repo == nil
    assert spec.write_repo == nil
    assert spec.read_issue_number == nil
    assert spec.token == nil
    assert spec.subject == "github-live-proof"
    assert spec.actor_id == "github-live-proof"
    assert spec.tenant_id == "tenant-github-live"
    assert spec.write_label == "jido-live-acceptance"
    assert spec.api_base_url == nil
    assert spec.timeout_ms == nil
  end

  test "read validation requires an explicit live gate and a repo" do
    assert {:error, missing} = LiveEnv.validate(:read, %{})
    assert missing == [@env.live, @env.repo]

    assert :ok =
             LiveEnv.validate(:read, %{
               @env.live => "1",
               @env.repo => "agentjido/jido_integration_v2"
             })
  end

  test "write validation requires the separate write gate" do
    assert {:error, missing} =
             LiveEnv.validate(:write, %{
               @env.live => "1",
               @env.repo => "agentjido/jido_integration_v2"
             })

    assert missing == [@env.live_write]
  end

  test "normalizes write settings and prefers the package token env" do
    spec =
      LiveEnv.spec(%{
        @env.live => "true",
        @env.live_write => "yes",
        @env.repo => "agentjido/jido_integration_v2",
        @env.write_repo => "agentjido/jido_integration_v2_sandbox",
        @env.read_issue_number => "42",
        @env.token => "gho_package",
        @env.fallback_token => "gho_generic",
        @env.subject => "octocat",
        @env.actor_id => "operator-1",
        @env.tenant_id => "tenant-1",
        @env.write_label => "bug",
        @env.api_base_url => "https://ghe.example.test/api/v3",
        @env.timeout_ms => "20000"
      })

    assert spec.read_enabled?
    assert spec.write_enabled?
    assert spec.repo == "agentjido/jido_integration_v2"
    assert spec.write_repo == "agentjido/jido_integration_v2_sandbox"
    assert spec.read_issue_number == 42
    assert spec.token == "gho_package"
    assert spec.subject == "octocat"
    assert spec.actor_id == "operator-1"
    assert spec.tenant_id == "tenant-1"
    assert spec.write_label == "bug"
    assert spec.api_base_url == "https://ghe.example.test/api/v3"
    assert spec.timeout_ms == 20_000
  end

  test "falls back to the read repo when no write repo is provided" do
    spec =
      LiveEnv.spec(%{
        @env.live => "1",
        @env.live_write => "1",
        @env.repo => "agentjido/jido_integration_v2"
      })

    assert spec.write_repo == "agentjido/jido_integration_v2"
  end

  test "treats malformed repo values as missing configuration" do
    assert {:error, missing} =
             LiveEnv.validate(:read, %{
               @env.live => "1",
               @env.repo => "not-a-repo"
             })

    assert missing == [@env.repo]
  end
end
