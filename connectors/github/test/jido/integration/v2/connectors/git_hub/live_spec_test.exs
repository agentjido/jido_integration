defmodule Jido.Integration.V2.Connectors.GitHub.LiveSpecTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.GitHub.LiveSpec

  test "auth mode uses deterministic defaults and does not require a repo" do
    assert {:ok, spec} = LiveSpec.parse(:auth, [])

    assert spec.mode == :auth
    assert spec.repo == nil
    assert spec.write_repo == nil
    assert spec.subject == "github-live-proof"
    assert spec.actor_id == "github-live-proof"
    assert spec.tenant_id == "tenant-github-live"
    assert spec.write_label == "jido-live-acceptance"
    assert spec.api_base_url == nil
    assert spec.timeout_ms == nil
  end

  test "read mode requires an explicit typed repo argument" do
    assert {:error, {:missing, ["--repo"]}} = LiveSpec.parse(:read, [])

    assert {:ok, spec} =
             LiveSpec.parse(:read, [
               "--repo",
               "agentjido/jido_integration_v2"
             ])

    assert spec.mode == :read
    assert spec.repo == "agentjido/jido_integration_v2"
    assert spec.write_repo == nil
  end

  test "tolerates a leading CLI argument separator" do
    assert {:ok, spec} =
             LiveSpec.parse(:read, [
               "--",
               "--repo",
               "agentjido/jido_integration_v2"
             ])

    assert spec.repo == "agentjido/jido_integration_v2"
  end

  test "write and all modes use a typed writable target without provider IDs" do
    assert {:ok, write_spec} =
             LiveSpec.parse(:write, [
               "--repo",
               "agentjido/jido_integration_v2"
             ])

    assert write_spec.write_repo == "agentjido/jido_integration_v2"
    refute Map.has_key?(write_spec, :read_issue_number)
    refute Map.has_key?(write_spec, :read_pr_number)

    assert {:ok, all_spec} =
             LiveSpec.parse(:all, [
               "--repo",
               "agentjido/jido_integration_v2",
               "--write-repo",
               "agentjido/jido_integration_v2_sandbox"
             ])

    assert all_spec.mode == :all
    assert all_spec.repo == "agentjido/jido_integration_v2"
    assert all_spec.write_repo == "agentjido/jido_integration_v2_sandbox"
  end

  test "normalizes optional typed live settings" do
    assert {:ok, spec} =
             LiveSpec.parse(:read, [
               "--repo=agentjido/jido_integration_v2",
               "--subject=octocat",
               "--actor-id=operator-1",
               "--tenant-id=tenant-1",
               "--write-label=bug",
               "--api-base-url=https://ghe.example.test/api/v3",
               "--timeout-ms=20000"
             ])

    assert spec.subject == "octocat"
    assert spec.actor_id == "operator-1"
    assert spec.tenant_id == "tenant-1"
    assert spec.write_label == "bug"
    assert spec.api_base_url == "https://ghe.example.test/api/v3"
    assert spec.timeout_ms == 20_000
  end

  test "rejects malformed repos, malformed integers, and unknown flags" do
    assert {:error, {:invalid_repo, "--repo", "not-a-repo"}} =
             LiveSpec.parse(:read, ["--repo", "not-a-repo"])

    assert {:error, {:invalid_integer, "--timeout-ms", "soon"}} =
             LiveSpec.parse(:read, [
               "--repo",
               "agentjido/jido_integration_v2",
               "--timeout-ms",
               "soon"
             ])

    assert {:error, {:unknown_flag, "--read-issue-number"}} =
             LiveSpec.parse(:read, [
               "--repo",
               "agentjido/jido_integration_v2",
               "--read-issue-number",
               "42"
             ])
  end
end
