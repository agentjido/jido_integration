defmodule Jido.Integration.V2AuditSubscriberTest do
  use Jido.Integration.V2.Platform.DurableCase

  alias Jido.Integration.V2
  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.InferenceRequest

  defmodule CloudHTTP do
  end

  setup do
    ControlPlane.reset!()

    Req.Test.stub(CloudHTTP, fn conn ->
      Req.Test.json(conn, %{
        "id" => "cmpl_platform_audit_subscriber_123",
        "model" => "gpt-4o-mini",
        "choices" => [
          %{
            "finish_reason" => "stop",
            "message" => %{
              "role" => "assistant",
              "content" => "Audit subscriber replay is alive."
            }
          }
        ],
        "usage" => %{
          "prompt_tokens" => 11,
          "completion_tokens" => 7,
          "total_tokens" => 18
        }
      })
    end)

    :ok
  end

  test "replays typed observer exports by durable run lineage" do
    assert audit_request = inference_request_fixture("tenant-audit-1", "inst-audit-1")

    assert {:ok, result} =
             V2.invoke_inference(
               audit_request,
               api_key: "cloud-fixture-token",
               req_http_options: [plug: {Req.Test, CloudHTTP}],
               run_id: "run-platform-audit-1",
               decision_ref: "decision-platform-audit-1",
               trace_id: "trace-platform-audit-1"
             )

    artifact = artifact_fixture(result.run.run_id, result.attempt.attempt_id)
    assert :ok = V2.record_artifact(artifact)

    assert V2.audit_export_kinds() == [
             "run.accepted",
             "attempt.recorded",
             "event.appended",
             "artifact.recorded"
           ]

    assert {:ok, exports} = V2.replay_audit_exports(result.run.run_id)

    assert Enum.count(exports, &(&1.export_kind == "run.accepted")) == 1
    assert Enum.count(exports, &(&1.export_kind == "attempt.recorded")) == 1
    assert Enum.count(exports, &(&1.export_kind == "artifact.recorded")) == 1
    assert Enum.count(exports, &(&1.export_kind == "event.appended")) == 5

    assert Enum.all?(exports, &(&1.trace_id == "trace-platform-audit-1"))
    assert Enum.all?(exports, &(&1.tenant_id == "tenant-audit-1"))
    assert Enum.all?(exports, &(&1.installation_id == "inst-audit-1"))
    assert Enum.all?(exports, &(&1.staleness == :live))

    assert [run_export] = Enum.filter(exports, &(&1.export_kind == "run.accepted"))
    assert run_export.payload["run"]["run_id"] == result.run.run_id

    assert run_export.payload["run"]["input"]["context"]["metadata"]["tenant_id"] ==
             "tenant-audit-1"

    assert [artifact_export] = Enum.filter(exports, &(&1.export_kind == "artifact.recorded"))
    assert artifact_export.payload["artifact"]["artifact_id"] == artifact.artifact_id

    assert {:ok, replayed_exports} = V2.replay_audit_exports(result.run.run_id)
    assert Enum.map(replayed_exports, & &1.export_id) == Enum.map(exports, & &1.export_id)
  end

  test "filters replay by the frozen Stage 14 export kinds" do
    request = inference_request_fixture("tenant-audit-filter", "inst-audit-filter")

    assert {:ok, result} =
             V2.invoke_inference(
               request,
               api_key: "cloud-fixture-token",
               req_http_options: [plug: {Req.Test, CloudHTTP}],
               run_id: "run-platform-audit-filter",
               decision_ref: "decision-platform-audit-filter",
               trace_id: "trace-platform-audit-filter"
             )

    artifact = artifact_fixture(result.run.run_id, result.attempt.attempt_id)
    assert :ok = V2.record_artifact(artifact)

    assert {:ok, artifact_exports} =
             V2.replay_audit_exports(
               result.run.run_id,
               event_types: ["artifact.recorded"]
             )

    assert Enum.map(artifact_exports, & &1.export_kind) == ["artifact.recorded"]

    assert {:error, :invalid_event_types} =
             V2.replay_audit_exports(result.run.run_id, event_types: ["run.failed"])

    assert {:error, :unknown_run} = V2.replay_audit_exports("run-missing")
  end

  test "surfaces missing trace and tenant scope as diagnostic replay posture" do
    request = inference_request_fixture(nil, nil)

    assert {:ok, result} =
             V2.invoke_inference(
               request,
               api_key: "cloud-fixture-token",
               req_http_options: [plug: {Req.Test, CloudHTTP}],
               run_id: "run-platform-audit-diagnostic",
               decision_ref: "decision-platform-audit-diagnostic"
             )

    assert {:ok, exports} = V2.replay_audit_exports(result.run.run_id)

    assert Enum.all?(exports, &(&1.staleness == :diagnostic_only))
    assert Enum.all?(exports, &(&1.trace_id == "diagnostic.missing_trace_id"))
    assert Enum.all?(exports, &(&1.tenant_id == "diagnostic.missing_tenant_id"))
    assert Enum.all?(exports, &is_nil(&1.installation_id))
  end

  defp inference_request_fixture(tenant_id, installation_id) do
    metadata =
      %{}
      |> maybe_put(:tenant_id, tenant_id)
      |> maybe_put(:installation_id, installation_id)

    InferenceRequest.new!(%{
      request_id: "req-platform-audit-#{System.unique_integer([:positive])}",
      operation: :generate_text,
      messages: [%{role: "user", content: "Summarize the audit subscriber seam"}],
      prompt: nil,
      model_preference: %{provider: "openai", id: "gpt-4o-mini"},
      target_preference: %{target_class: "cloud_provider"},
      stream?: false,
      tool_policy: %{},
      output_constraints: %{},
      metadata: metadata
    })
  end

  defp artifact_fixture(run_id, attempt_id) do
    checksum = "sha256:" <> String.duplicate("d", 64)

    ArtifactRef.new!(%{
      artifact_id: "artifact-audit-#{System.unique_integer([:positive])}",
      run_id: run_id,
      attempt_id: attempt_id,
      artifact_type: :tool_output,
      transport_mode: :object_store,
      checksum: checksum,
      size_bytes: 64,
      payload_ref: %{
        store: "s3",
        key: "audit-subscriber/#{run_id}/#{attempt_id}",
        ttl_s: 86_400,
        access_control: :run_scoped,
        checksum: checksum,
        size_bytes: 64
      },
      retention_class: "observer_export",
      redaction_status: :clear,
      metadata: %{
        surface: "audit_subscriber",
        producer: "platform_test"
      }
    })
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
