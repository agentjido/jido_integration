defmodule Jido.Integration.V2.Connectors.Linear.LiveSpecTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.Linear.LiveSpec

  test "auth mode requires an explicit typed credential source" do
    assert {:error, {:missing, ["--api-key-stdin", "--api-key-file"]}} =
             LiveSpec.parse(:auth, [])

    assert {:ok, spec} = LiveSpec.parse(:auth, ["--api-key-stdin"])

    assert spec.mode == :auth
    assert spec.api_key_source == :stdin
    assert spec.subject == "linear-live-proof"
    assert spec.actor_id == "linear-live-proof"
    assert spec.tenant_id == "tenant-linear-live"
    assert spec.read_limit == 10
    assert spec.keep_terminal_comment? == false
    assert spec.api_base_url == nil
    assert spec.timeout_ms == nil
  end

  test "read mode uses dynamic provider discovery without static issue selectors" do
    assert {:ok, spec} =
             LiveSpec.parse(:read, [
               "--api-key-file",
               "/operator/linear-token",
               "--read-limit",
               "3"
             ])

    assert spec.mode == :read
    assert spec.api_key_source == {:file, "/operator/linear-token"}
    assert spec.read_limit == 3
    refute Map.has_key?(spec, :issue_id)
    refute Map.has_key?(spec, :workflow_state_id)
  end

  test "write and all modes keep provider ids out of the operator contract" do
    assert {:ok, write_spec} = LiveSpec.parse(:write, ["--api-key-stdin"])
    assert write_spec.mode == :write
    refute Map.has_key?(write_spec, :issue_id)
    refute Map.has_key?(write_spec, :comment_id)
    refute Map.has_key?(write_spec, :state_id)

    assert {:ok, all_spec} = LiveSpec.parse(:all, ["--api-key-stdin"])
    assert all_spec.mode == :all
  end

  test "normalizes optional typed live settings" do
    assert {:ok, spec} =
             LiveSpec.parse(:read, [
               "--api-key-stdin",
               "--subject=operator",
               "--actor-id=operator-1",
               "--tenant-id=tenant-1",
               "--api-base-url=https://linear.example.test/graphql",
               "--timeout-ms=20000",
               "--read-limit=25",
               "--keep-terminal-comment"
             ])

    assert spec.subject == "operator"
    assert spec.actor_id == "operator-1"
    assert spec.tenant_id == "tenant-1"
    assert spec.api_base_url == "https://linear.example.test/graphql"
    assert spec.timeout_ms == 20_000
    assert spec.read_limit == 25
    assert spec.keep_terminal_comment? == true
  end

  test "rejects malformed integers, duplicate credential sources, and unknown provider id flags" do
    assert {:error, {:invalid_integer, "--timeout-ms", "soon"}} =
             LiveSpec.parse(:read, [
               "--api-key-stdin",
               "--timeout-ms",
               "soon"
             ])

    assert {:error, {:duplicate_credential_source, ["--api-key-stdin", "--api-key-file"]}} =
             LiveSpec.parse(:read, [
               "--api-key-stdin",
               "--api-key-file",
               "/operator/linear-token"
             ])

    assert {:error, {:unknown_flag, "--issue-id"}} =
             LiveSpec.parse(:read, [
               "--api-key-stdin",
               "--issue-id",
               "lin-issue-123"
             ])

    assert {:error, {:unknown_flag, "--comment-id"}} =
             LiveSpec.parse(:write, [
               "--api-key-stdin",
               "--comment-id",
               "lin-comment-123"
             ])

    assert {:error, {:unknown_flag, "--state-id"}} =
             LiveSpec.parse(:write, [
               "--api-key-stdin",
               "--state-id",
               "lin-state-123"
             ])
  end
end
