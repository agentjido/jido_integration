defmodule Jido.Integration.V2.RuntimeRouter.AgentRuntimeReceiptAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.AgentInterop.Receipt
  alias Jido.Integration.V2.RuntimeResult
  alias Jido.Integration.V2.RuntimeRouter.AgentRuntimeReceiptAdapter

  test "builds generic agent receipt from runtime router result and context refs" do
    runtime_result =
      RuntimeResult.new!(%{
        output: %{
          adapter: :execution_plane_tre,
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
        trace_ref: "trace://agent/1",
        evidence_refs: ["evidence://agent/1"]
      })

    assert %Receipt{} = receipt
    assert receipt.ledger_ref == "ledger://run/1"
    assert receipt.lower_invocation_ref == "agent-invocation://doc-review/1"
    assert receipt.capability_ref == "agent-capability://doc-review/summarize"
    assert receipt.authority_ref == "authority://agent/doc-review"
    assert receipt.status == :succeeded
    assert receipt.output_summary["source"] == nil
    assert receipt.metadata["source"] == "runtime_router"
  end

  test "requires ledger and authority refs" do
    runtime_result = RuntimeResult.new!(%{output: %{}, events: [], artifacts: []})

    error =
      assert_raise ArgumentError, fn ->
        AgentRuntimeReceiptAdapter.from_runtime_result!(runtime_result, %{
          receipt_ref: "agent-receipt://doc-review/1",
          lower_invocation_ref: "agent-invocation://doc-review/1",
          capability_ref: "agent-capability://doc-review/summarize",
          idempotency_key: "idem-agent-1"
        })
      end

    assert String.contains?(Exception.message(error), "ledger_ref")
  end
end
