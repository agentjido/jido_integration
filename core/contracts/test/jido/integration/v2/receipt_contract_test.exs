defmodule Jido.Integration.V2.ReceiptContractTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.{ArtifactRef, Attempt, CredentialRef, Event, Receipt, Run}

  @artifact_ref %{
    "artifact_id" => "artifact:lower:1",
    "content_hash" => "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "content_hash_alg" => "sha256",
    "byte_size" => 120_000,
    "schema_name" => "JidoIntegration.NormalizedOutcome.v1",
    "schema_hash" => "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "schema_hash_alg" => "sha256",
    "media_type" => "application/json",
    "producer_repo" => "jido_integration",
    "tenant_scope" => "tenant-1",
    "sensitivity_class" => "tenant_sensitive",
    "store_security_posture_ref" => "jido_integration.claim_check_hot.security.v1",
    "encryption_posture_ref" => "unavailable_fail_closed",
    "retrieval_owner" => "jido_integration",
    "existing_fetch_or_restore_path" => "existing_claim_check_fetch",
    "safe_actions" => ["quarantine", "operator_review"],
    "queue_key" => "tenant-1:installation-1:run-1",
    "oversize_action" => "ref_required",
    "release_manifest_ref" => "phase5-v7-artifact-boundary"
  }

  test "completed receipts expose a Mezzanine lower receipt map and terminal outcome envelope" do
    receipt =
      receipt!(
        status: :completed,
        metadata: %{
          "ji_submission_key" => "submission-key-1",
          "normalized_outcome_ref" => @artifact_ref,
          "artifact_refs" => ["artifact:lower:1"],
          "lifecycle_hints" => %{"next" => "publish_review"}
        }
      )

    assert Receipt.terminal?(receipt)

    assert Receipt.to_lower_receipt_map(receipt) == %{
             "artifact_refs" => ["artifact:lower:1"],
             "attempt_id" => "run-1:1",
             "failure_kind" => nil,
             "ji_submission_key" => "submission-key-1",
             "lifecycle_hints" => %{"next" => "publish_review"},
             "normalized_outcome_ref" => @artifact_ref,
             "session_ref" => nil,
             "boundary_session_ref" => nil,
             "turn_ref" => nil,
             "workspace_ref" => nil,
             "worker_ref" => nil,
             "execution_plane_ref" => nil,
             "route_ref" => "route-1",
             "outcome_ref" => nil,
             "token_totals" => %{},
             "rate_limits" => %{},
             "authority_refs" => [],
             "observed_at" => DateTime.to_iso8601(receipt.observed_at),
             "event_refs" => [],
             "receipt_id" => "run-1:run-1:1:execution",
             "receipt_kind" => "execution",
             "provider_refs" => %{},
             "route_id" => "route-1",
             "routing_facts" => %{"terminal_class" => "completed"},
             "run_id" => "run-1",
             "state" => "completed",
             "terminal?" => true
           }

    assert {:ok, outcome} =
             Receipt.to_execution_outcome(receipt, %{
               "text" => "done",
               "normalized_outcome_ref" => @artifact_ref
             })

    assert outcome.status == :ok
    assert outcome.receipt_id == receipt.receipt_id
    assert outcome.lower_receipt["state"] == "completed"
    assert outcome.normalized_outcome["text"] == "done"
    assert outcome.lifecycle_hints == %{"next" => "publish_review"}
    assert outcome.failure_kind == nil
    assert outcome.artifact_refs == ["artifact:lower:1"]
  end

  test "terminal failure, malformed protocol, timeout, and cancellation states stay typed" do
    cases = [
      {:failed, "execution_failed", :error, :execution_failed},
      {:failed, "malformed_protocol", :error, :malformed_protocol},
      {:timeout, "timeout", :error, :timeout},
      {:cancelled, "cancelled", :cancelled, nil}
    ]

    for {state, failure_kind, outcome_status, expected_failure_kind} <- cases do
      receipt = receipt!(status: state, metadata: %{"failure_kind" => failure_kind})

      assert Receipt.terminal?(receipt)

      lower_receipt = Receipt.to_lower_receipt_map(receipt)
      assert lower_receipt["state"] == Atom.to_string(state)
      assert lower_receipt["terminal?"] == true
      assert lower_receipt["failure_kind"] == failure_kind

      assert {:ok, outcome} = Receipt.to_execution_outcome(receipt, %{"state" => state})
      assert outcome.status == outcome_status
      assert outcome.failure_kind == expected_failure_kind
      assert outcome.lower_receipt["routing_facts"]["terminal_class"] == Atom.to_string(state)
    end
  end

  test "lower records project provider/event/artifact refs without raw provider payloads" do
    run = run!(status: :completed)
    attempt = attempt!(run.run_id, status: :completed)

    event =
      Event.new!(%{
        event_id: "event-provider-tool-1",
        run_id: run.run_id,
        attempt: 1,
        seq: 7,
        type: "codex.host_tool_completed",
        payload: %{
          "provider_session_id" => "codex-thread-1",
          "provider_turn_id" => "turn-1",
          "provider_request_id" => "request-1",
          "provider_item_id" => "item-1",
          "provider_tool_call_id" => "tool-call-1",
          "provider_message_id" => "message-1",
          "tool_name" => "linear.comment.update",
          "approval_id" => "approval-1",
          "raw_provider_body" => %{"must" => "not cross"}
        }
      })

    artifact = artifact!(run.run_id, attempt.attempt_id)

    assert {:ok, receipt} =
             Receipt.from_lower_records(run, attempt, [event], [artifact],
               ji_submission_key: "submission-key-1",
               lifecycle_hints: %{"next" => "review"}
             )

    lower_receipt = Receipt.to_lower_receipt_map(receipt)

    assert lower_receipt["run_id"] == run.run_id
    assert lower_receipt["attempt_id"] == attempt.attempt_id
    assert lower_receipt["artifact_refs"] == [artifact.artifact_id]

    assert lower_receipt["event_refs"] == [
             %{
               "event_id" => "event-provider-tool-1",
               "type" => "codex.host_tool_completed",
               "seq" => 7,
               "attempt_id" => attempt.attempt_id,
               "provider_session_id" => "codex-thread-1",
               "provider_turn_id" => "turn-1",
               "provider_request_id" => "request-1",
               "provider_item_id" => "item-1",
               "provider_tool_call_id" => "tool-call-1",
               "provider_message_id" => "message-1",
               "tool_name" => "linear.comment.update",
               "approval_id" => "approval-1"
             }
           ]

    assert lower_receipt["provider_refs"] == %{
             "provider_session_id" => "codex-thread-1",
             "provider_turn_id" => "turn-1",
             "provider_request_id" => "request-1",
             "provider_item_id" => "item-1",
             "provider_tool_call_id" => "tool-call-1",
             "provider_message_id" => "message-1",
             "tool_name" => "linear.comment.update",
             "approval_id" => "approval-1"
           }

    refute inspect(lower_receipt) =~ "raw_provider_body"
  end

  test "lower receipts carry S0 session, turn, workspace, route, outcome, and authority refs" do
    run = run!(status: :completed)
    attempt = attempt!(run.run_id, status: :completed)

    assert {:ok, receipt} =
             Receipt.from_lower_records(run, attempt, [], [],
               session_ref: "session-1",
               boundary_session_ref: "boundary-session-1",
               turn_ref: "turn-1",
               workspace_ref: "workspace-1",
               worker_ref: "worker-1",
               execution_plane_ref: "execution-plane-1",
               route_ref: "route-1",
               outcome_ref: "outcome-1",
               token_totals: %{"input" => 10, "output" => 2},
               rate_limits: %{"remaining" => 99},
               authority_refs: ["authority-1"]
             )

    lower_receipt = Receipt.to_lower_receipt_map(receipt)

    assert lower_receipt["session_ref"] == "session-1"
    assert lower_receipt["boundary_session_ref"] == "boundary-session-1"
    assert lower_receipt["turn_ref"] == "turn-1"
    assert lower_receipt["workspace_ref"] == "workspace-1"
    assert lower_receipt["worker_ref"] == "worker-1"
    assert lower_receipt["execution_plane_ref"] == "execution-plane-1"
    assert lower_receipt["route_ref"] == "route-1"
    assert lower_receipt["outcome_ref"] == "outcome-1"
    assert lower_receipt["token_totals"] == %{"input" => 10, "output" => 2}
    assert lower_receipt["rate_limits"] == %{"remaining" => 99}
    assert lower_receipt["authority_refs"] == ["authority-1"]
  end

  test "workflow receipt signal attrs match the Mezzanine signal contract shape" do
    receipt = receipt!(status: :approval_required)

    assert Receipt.to_workflow_receipt_signal_attrs(receipt,
             tenant_ref: "tenant-1",
             installation_ref: "installation-1",
             resource_ref: "execution-1",
             workflow_id: "workflow-1",
             authority_packet_ref: "authority-1",
             permission_decision_ref: "permission-1",
             trace_id: "trace-1",
             correlation_id: "correlation-1",
             release_manifest_ref: "release-1"
           ) == %{
             tenant_ref: "tenant-1",
             installation_ref: "installation-1",
             resource_ref: "execution-1",
             workflow_id: "workflow-1",
             signal_id: "signal:run-1:run-1:1:execution",
             signal_name: "lower_receipt",
             signal_version: "v1",
             lower_receipt_ref: "run-1:run-1:1:execution",
             lower_run_ref: "run-1",
             lower_attempt_ref: "run-1:1",
             lower_event_ref: nil,
             authority_packet_ref: "authority-1",
             permission_decision_ref: "permission-1",
             idempotency_key: "receipt:run-1:run-1:1:execution:approval_required",
             trace_id: "trace-1",
             correlation_id: "correlation-1",
             release_manifest_ref: "release-1",
             receipt_state: "approval_required",
             terminal?: false,
             routing_facts: %{
               "terminal_class" => "non_terminal",
               "waiting_on" => "approval_required"
             }
           }
  end

  test "unknown failure kinds are not promoted into new atoms" do
    receipt = receipt!(status: :failed, metadata: %{"failure_kind" => "provider_new_failure"})

    assert {:ok, outcome} = Receipt.to_execution_outcome(receipt, %{"state" => "failed"})
    assert outcome.lower_receipt["failure_kind"] == "provider_new_failure"
    assert outcome.failure_kind == :execution_failed
  end

  test "blocked, input-required, and approval-required receipts are non-terminal workflow states" do
    for state <- [:blocked, :input_required, :approval_required] do
      receipt = receipt!(status: state, metadata: %{"waiting_on" => Atom.to_string(state)})

      refute Receipt.terminal?(receipt)

      lower_receipt = Receipt.to_lower_receipt_map(receipt)
      assert lower_receipt["state"] == Atom.to_string(state)
      assert lower_receipt["terminal?"] == false

      assert lower_receipt["routing_facts"] == %{
               "terminal_class" => "non_terminal",
               "waiting_on" => Atom.to_string(state)
             }

      assert {:error, {:non_terminal_receipt, ^state}} =
               Receipt.to_execution_outcome(receipt, %{})
    end
  end

  defp receipt!(overrides) do
    defaults = [
      run_id: "run-1",
      attempt_id: "run-1:1",
      route_id: "route-1",
      receipt_kind: :execution,
      status: :completed
    ]

    defaults
    |> Keyword.merge(overrides)
    |> Receipt.new!()
  end

  defp run!(attrs) do
    defaults = %{
      run_id: "run-1",
      capability_id: "codex.session.turn",
      runtime_class: :session,
      input: %{
        metadata: %{
          tenant_id: "tenant-1",
          installation_id: "installation-1",
          ji_submission_key: "submission-key-1"
        }
      },
      credential_ref:
        CredentialRef.new!(%{
          id: "credref-1",
          connection_id: "connection-1",
          subject: "tenant-1",
          profile_id: "default",
          scopes: []
        })
    }

    defaults
    |> Map.merge(Map.new(attrs))
    |> Run.new!()
  end

  defp attempt!(run_id, attrs) do
    defaults = %{
      run_id: run_id,
      attempt: 1,
      runtime_class: :session,
      credential_lease_id: "lease-1",
      output: %{"state" => "completed"}
    }

    defaults
    |> Map.merge(Map.new(attrs))
    |> Attempt.new!()
  end

  defp artifact!(run_id, attempt_id) do
    checksum = "sha256:" <> String.duplicate("c", 64)

    ArtifactRef.new!(%{
      artifact_id: "artifact-lower-record-1",
      run_id: run_id,
      attempt_id: attempt_id,
      artifact_type: :tool_output,
      transport_mode: :object_store,
      checksum: checksum,
      size_bytes: 128,
      payload_ref: %{
        store: "s3",
        key: "lower-record/#{run_id}/#{attempt_id}",
        ttl_s: 86_400,
        access_control: :run_scoped,
        checksum: checksum,
        size_bytes: 128
      },
      retention_class: "review_output",
      redaction_status: :clear,
      metadata: %{}
    })
  end
end
