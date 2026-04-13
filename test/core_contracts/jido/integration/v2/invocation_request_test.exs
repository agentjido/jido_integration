defmodule Jido.Integration.V2.InvocationRequestTest do
  use ExUnit.Case

  alias Jido.Integration.V2.InvocationRequest

  test "normalizes stable invoke fields and derives the requested capability allowlist" do
    request =
      InvocationRequest.new!(%{
        "capability_id" => "github.issue.create",
        "connection_id" => "connection-1",
        "input" => %{"repo" => "agentjido/jido_integration_v2"},
        "actor_id" => "desk-operator",
        "tenant_id" => "tenant-1",
        "environment" => "prod",
        "trace_id" => "trace-1",
        "sandbox" => %{
          "level" => "strict",
          "egress" => "restricted",
          "approvals" => "manual",
          "file_scope" => "/srv/tenant-1",
          "allowed_tools" => ["github.api.issue.create"]
        },
        "target_id" => "target-operator",
        "aggregator_id" => "gateway-1",
        "aggregator_epoch" => 2,
        "extensions" => [idempotency_key: "req-1", timeout_ms: 5_000]
      })

    assert request.capability_id == "github.issue.create"
    assert request.connection_id == "connection-1"
    assert request.input == %{"repo" => "agentjido/jido_integration_v2"}
    assert request.actor_id == "desk-operator"
    assert request.tenant_id == "tenant-1"
    assert request.environment == "prod"
    assert request.trace_id == "trace-1"
    assert request.allowed_operations == ["github.issue.create"]
    assert request.target_id == "target-operator"
    assert request.aggregator_id == "gateway-1"
    assert request.aggregator_epoch == 2
    assert request.extensions == [idempotency_key: "req-1", timeout_ms: 5_000]

    assert request.sandbox == %{
             level: :strict,
             egress: :restricted,
             approvals: :manual,
             file_scope: "/srv/tenant-1",
             allowed_tools: ["github.api.issue.create"]
           }

    assert InvocationRequest.to_opts(request) == [
             connection_id: "connection-1",
             actor_id: "desk-operator",
             tenant_id: "tenant-1",
             environment: "prod",
             trace_id: "trace-1",
             allowed_operations: ["github.issue.create"],
             sandbox: %{
               level: :strict,
               egress: :restricted,
               approvals: :manual,
               file_scope: "/srv/tenant-1",
               allowed_tools: ["github.api.issue.create"]
             },
             target_id: "target-operator",
             aggregator_id: "gateway-1",
             aggregator_epoch: 2,
             idempotency_key: "req-1",
             timeout_ms: 5_000
           ]
  end

  test "rejects invalid public invoke fields" do
    assert_raise ArgumentError, ~r/capability_id must be a non-empty string/, fn ->
      InvocationRequest.new!(%{capability_id: "  "})
    end

    assert_raise ArgumentError, ~r/input must be a map/, fn ->
      InvocationRequest.new!(%{capability_id: "github.issue.create", input: :invalid})
    end

    assert_raise ArgumentError, ~r/aggregator_epoch must be a positive integer/, fn ->
      InvocationRequest.new!(%{
        capability_id: "github.issue.create",
        aggregator_epoch: 0
      })
    end

    assert_raise ArgumentError, ~r/extensions must be a keyword list/, fn ->
      InvocationRequest.new!(%{
        capability_id: "github.issue.create",
        extensions: %{idempotency_key: "req-1"}
      })
    end

    assert_raise ArgumentError,
                 ~r/credential_ref is not part of the public invocation contract/,
                 fn ->
                   InvocationRequest.new!(%{
                     capability_id: "github.issue.create",
                     credential_ref: %{id: "cred-1", subject: "desk-operator"}
                   })
                 end

    assert_raise ArgumentError,
                 ~r/credential_ref is not part of the public invocation contract/,
                 fn ->
                   InvocationRequest.new!(%{
                     capability_id: "github.issue.create",
                     extensions: [credential_ref: %{id: "cred-1", subject: "desk-operator"}]
                   })
                 end

    assert_raise ArgumentError, ~r/extensions must not redefine reserved invoke fields/, fn ->
      InvocationRequest.new!(%{
        capability_id: "github.issue.create",
        extensions: [connection_id: "connection-1"]
      })
    end
  end

  test "to_opts rejects credential_ref extensions on manually constructed requests" do
    assert_raise ArgumentError,
                 ~r/credential_ref is not part of the public invocation contract/,
                 fn ->
                   InvocationRequest.to_opts(%InvocationRequest{
                     capability_id: "github.issue.create",
                     extensions: [credential_ref: %{id: "cred-1", subject: "desk-operator"}]
                   })
                 end
  end
end
