defmodule Jido.Integration.V2.ControlPlane.AgentRuntimeReceiptAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.AgentInterop.Receipt
  alias Jido.Integration.V2.ControlPlane.AgentRuntimeReceiptAdapter
  alias Jido.Integration.V2.RuntimeResult

  test "builds generic agent receipt from control-plane result and context refs" do
    runtime_result =
      RuntimeResult.new!(%{
        output: %{
          adapter: :fake_tre,
          capability_id: "agent-capability://doc-review/summarize",
          lower_request_ref: "agent-invocation://doc-review/1",
          lower_runtime_kind: :tre_rhai
        },
        runtime_ref_id: "runtime://doc-review/1",
        events: [%{type: "agent.completed"}],
        artifacts: []
      })

    receipt =
      AgentRuntimeReceiptAdapter.from_runtime_result!(runtime_result, %{
        receipt_ref: "agent-receipt://doc-review/1",
        ledger_ref: "ledger://run/1",
        authority_ref: "authority://agent/doc-review",
        idempotency_key: "idem-agent-1",
        trace_ref: "trace://agent/1"
      })

    assert %Receipt{} = receipt
    assert receipt.ledger_ref == "ledger://run/1"
    assert receipt.status == :succeeded
    assert receipt.metadata["source"] == "control_plane"
  end

  test "failed runtime result becomes failed agent receipt" do
    runtime_result =
      RuntimeResult.new!(%{
        output: %{error: "denied"},
        runtime_ref_id: "runtime://doc-review/1",
        events: [],
        artifacts: []
      })

    receipt =
      AgentRuntimeReceiptAdapter.from_runtime_result!(runtime_result, %{
        receipt_ref: "agent-receipt://doc-review/1",
        ledger_ref: "ledger://run/1",
        lower_invocation_ref: "agent-invocation://doc-review/1",
        capability_ref: "agent-capability://doc-review/summarize",
        authority_ref: "authority://agent/doc-review",
        idempotency_key: "idem-agent-1"
      })

    assert receipt.status == :failed
  end
end
