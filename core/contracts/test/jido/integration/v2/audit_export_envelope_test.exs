defmodule Jido.Integration.V2.AuditExportEnvelopeTest do
  use ExUnit.Case

  alias Jido.Integration.V2.AuditExportEnvelope

  test "accepts the frozen observer export envelope contract" do
    envelope =
      AuditExportEnvelope.new!(%{
        export_id: "jido://v2/audit_export/run.accepted/run-42",
        export_kind: "run.accepted",
        trace_id: "trace-42",
        tenant_id: "tenant-42",
        installation_id: "inst-42",
        run_id: "run-42",
        staleness: :live,
        payload: %{
          "run" => %{
            "run_id" => "run-42",
            "capability_id" => "inference.execute"
          }
        }
      })

    assert envelope.export_kind == "run.accepted"
    assert envelope.staleness == :live
    assert envelope.payload["run"]["capability_id"] == "inference.execute"
  end

  test "rejects unsupported export kinds" do
    assert_raise ArgumentError, ~r/audit_export.export_kind/, fn ->
      AuditExportEnvelope.new!(%{
        export_id: "jido://v2/audit_export/run.failed/run-42",
        export_kind: "run.failed",
        trace_id: "trace-42",
        tenant_id: "tenant-42",
        run_id: "run-42",
        staleness: :diagnostic_only,
        payload: %{"run" => %{"run_id" => "run-42"}}
      })
    end
  end
end
