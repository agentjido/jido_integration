defmodule Jido.Integration.V2.Conformance.AgentInteropContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.AgentInterop.Capability
  alias Jido.Integration.AgentInterop.Descriptor
  alias Jido.Integration.AgentInterop.Receipt

  test "generic interop descriptor requires policy and credential lease refs" do
    descriptor =
      Descriptor.new!(%{
        interop_ref: "agent-interop://tenant/doc-review",
        name: "Document Review Agent",
        version: "1",
        protocol_family: "http",
        endpoint_ref: "endpoint://agent/doc-review",
        capability_refs: ["agent-capability://doc-review/summarize"],
        auth_binding_ref: "credential-binding://agent/doc-review",
        policy_ref: "policy://agent/doc-review"
      })

    assert descriptor.protocol_family == :http
    assert descriptor.auth_binding_ref == "credential-binding://agent/doc-review"
    assert descriptor.policy_ref == "policy://agent/doc-review"
  end

  test "capabilities are generic classes and receipts carry reduction refs" do
    capability =
      Capability.new!(%{
        capability_ref: "agent-capability://doc-review/summarize",
        class: :external_agent_turn,
        operation: "summarize",
        input_schema_ref: "schema://doc-review/input",
        output_schema_ref: "schema://doc-review/output",
        side_effect_class: :read,
        credential_classes: ["api-token-lease"]
      })

    receipt =
      Receipt.new!(%{
        receipt_ref: "agent-receipt://doc-review/1",
        ledger_ref: "ledger://run/1",
        lower_invocation_ref: "agent-invocation://doc-review/1",
        runtime_family: :interop,
        capability_ref: capability.capability_ref,
        authority_ref: "authority://agent/doc-review",
        idempotency_key: "idem-agent-1",
        status: :succeeded,
        evidence_refs: ["evidence://agent/1"]
      })

    assert receipt.ledger_ref == "ledger://run/1"
    assert receipt.authority_ref == "authority://agent/doc-review"
    refute Receipt.can_transition?(receipt.status, :started)
  end

  test "agent interop library does not generate concrete external-agent protocol modules" do
    app = Application.spec(:jido_integration_agent_interop_contracts, :modules)

    assert is_list(app)

    Enum.each(app, fn module ->
      module_name = Atom.to_string(module)

      refute String.contains?(module_name, "Agent" <> "2Agent")
      refute String.contains?(module_name, "A" <> "2A")
    end)
  end
end
