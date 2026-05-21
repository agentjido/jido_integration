defmodule Jido.Integration.AgentInterop.ContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.AgentInterop.Capability
  alias Jido.Integration.AgentInterop.Descriptor
  alias Jido.Integration.AgentInterop.Invocation
  alias Jido.Integration.AgentInterop.PolicyRef
  alias Jido.Integration.AgentInterop.Receipt
  alias Jido.Integration.AgentRuntimeCapability
  alias Jido.Integration.AgentRuntimeReceipt

  test "descriptor accepts generic protocol facts without concrete protocol-specific fields" do
    descriptor =
      Descriptor.new!(%{
        interop_ref: "agent-interop://tenant/doc-review",
        name: "Document Review Agent",
        version: "2026-05-21",
        protocol_family: :http,
        endpoint_ref: "endpoint://agent/doc-review",
        capability_refs: ["agent-capability://doc-review/summarize"],
        auth_binding_ref: "credential-binding://agent/doc-review",
        policy_ref: "policy://agent/doc-review",
        input_schema_ref: "schema://agent/doc-review/input",
        output_schema_ref: "schema://agent/doc-review/output",
        streaming?: true,
        resumable?: false,
        external_spec_refs: ["spec://external-agent/http-generic"],
        metadata: %{"purpose" => "proof"}
      })

    assert descriptor.protocol_family == :http
    assert descriptor.policy_ref == "policy://agent/doc-review"
    assert descriptor.auth_binding_ref == "credential-binding://agent/doc-review"

    assert Descriptor.to_map(descriptor)["capability_refs"] == [
             "agent-capability://doc-review/summarize"
           ]
  end

  test "descriptor rejects concrete protocol-only fields and raw endpoint material" do
    error =
      assert_raise ArgumentError, fn ->
        Descriptor.new!(%{
          interop_ref: "agent-interop://tenant/doc-review",
          name: "Document Review Agent",
          version: "1",
          protocol_family: :http,
          endpoint_ref: "endpoint://agent/doc-review",
          capability_refs: ["agent-capability://doc-review/summarize"],
          auth_binding_ref: "credential-binding://agent/doc-review",
          policy_ref: "policy://agent/doc-review",
          protocol_specific_required_url: "https://example.invalid/protocol-card"
        })
      end

    assert String.contains?(Exception.message(error), "unknown field")

    error =
      assert_raise ArgumentError, fn ->
        Descriptor.new!(%{
          interop_ref: "agent-interop://tenant/doc-review",
          name: "Document Review Agent",
          version: "1",
          protocol_family: :http,
          endpoint_ref: "endpoint://agent/doc-review",
          capability_refs: ["agent-capability://doc-review/summarize"],
          auth_binding_ref: "credential-binding://agent/doc-review",
          policy_ref: "policy://agent/doc-review",
          metadata: %{"endpoint_url" => "https://example.invalid/run"}
        })
      end

    assert String.contains?(Exception.message(error), "raw endpoint material")
  end

  test "descriptor rejects raw credentials and requires governed refs" do
    error =
      assert_raise ArgumentError, fn ->
        Descriptor.new!(%{
          interop_ref: "agent-interop://tenant/doc-review",
          name: "Document Review Agent",
          version: "1",
          protocol_family: :http,
          endpoint_ref: "endpoint://agent/doc-review",
          capability_refs: ["agent-capability://doc-review/summarize"],
          auth_binding_ref: "credential-binding://agent/doc-review",
          policy_ref: "policy://agent/doc-review",
          metadata: %{"access_token" => "cleartext"}
        })
      end

    assert String.contains?(Exception.message(error), "raw credential material")

    error =
      assert_raise ArgumentError, fn ->
        Descriptor.new!(%{
          interop_ref: "agent-interop://tenant/doc-review",
          name: "Document Review Agent",
          version: "1",
          protocol_family: :http,
          endpoint_ref: "endpoint://agent/doc-review",
          capability_refs: ["agent-capability://doc-review/summarize"],
          auth_binding_ref: "credential-binding://agent/doc-review"
        })
      end

    assert String.contains?(Exception.message(error), "policy_ref")
  end

  test "capability, policy ref, and invocation require authority and lease-style refs" do
    capability =
      Capability.new!(%{
        capability_ref: "agent-capability://doc-review/summarize",
        class: "external_agent_turn",
        operation: "summarize",
        input_schema_ref: "schema://doc-review/input",
        output_schema_ref: "schema://doc-review/output",
        side_effect_class: "read",
        requires_approval?: false,
        artifact_posture: "claim_checked",
        credential_classes: ["api-token-lease"]
      })

    assert capability.class == :external_agent_turn
    assert AgentRuntimeCapability.contract_name() == Capability.contract_name()

    policy_ref =
      PolicyRef.new!(%{
        policy_ref: "policy://agent/doc-review",
        authority_ref: "authority://agent/doc-review",
        policy_profile_ref: "policy-profile://standard"
      })

    invocation =
      Invocation.new!(%{
        invocation_ref: "agent-invocation://doc-review/1",
        interop_ref: "agent-interop://tenant/doc-review",
        capability_ref: capability.capability_ref,
        policy_ref: policy_ref.policy_ref,
        authority_ref: policy_ref.authority_ref,
        ledger_ref: "ledger://run/1",
        idempotency_key: "idem-agent-1",
        input_ref: "payload://input/1",
        input_summary: %{"document_count" => 1},
        runtime_family: :interop,
        trace_ref: "trace://agent/1"
      })

    assert invocation.ledger_ref == "ledger://run/1"
    assert invocation.authority_ref == "authority://agent/doc-review"
  end

  test "runtime receipt enforces ledger, authority, idempotency, and bounded transitions" do
    receipt =
      Receipt.new!(%{
        receipt_ref: "agent-receipt://doc-review/1",
        ledger_ref: "ledger://run/1",
        lower_invocation_ref: "agent-invocation://doc-review/1",
        runtime_family: :interop,
        capability_ref: "agent-capability://doc-review/summarize",
        authority_ref: "authority://agent/doc-review",
        idempotency_key: "idem-agent-1",
        status: :started,
        output_summary: %{"state" => "running"},
        evidence_refs: [],
        trace_ref: "trace://agent/1"
      })

    assert Receipt.can_transition?(:started, :pending)
    assert Receipt.can_transition?(:pending, :succeeded)
    refute Receipt.can_transition?(:succeeded, :started)

    terminal = Receipt.transition!(receipt, :succeeded, output_ref: "payload://output/1")
    assert terminal.status == :succeeded
    assert terminal.output_ref == "payload://output/1"
    assert AgentRuntimeReceipt.contract_name() == Receipt.contract_name()

    error =
      assert_raise ArgumentError, fn ->
        Receipt.transition!(terminal, :started)
      end

    assert String.contains?(
             Exception.message(error),
             "invalid agent runtime receipt status transition"
           )

    error =
      assert_raise ArgumentError, fn ->
        Receipt.new!(%{
          receipt_ref: "agent-receipt://doc-review/1",
          lower_invocation_ref: "agent-invocation://doc-review/1",
          runtime_family: :interop,
          capability_ref: "agent-capability://doc-review/summarize",
          authority_ref: "authority://agent/doc-review",
          idempotency_key: "idem-agent-1",
          status: :started
        })
      end

    assert String.contains?(Exception.message(error), "ledger_ref")
  end

  test "library code has no concrete external-agent protocol modules" do
    lib_root = Path.expand("../../lib", __DIR__)

    lib_root
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.each(fn path ->
      content = File.read!(path)
      basename = Path.basename(path)

      refute String.contains?(content, "Agent" <> "2Agent")
      refute String.contains?(content, "A" <> "2A")
      refute String.contains?(String.downcase(basename), "a" <> "2a")
    end)
  end
end
