defmodule Jido.Integration.V2.RetryPostureContractTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.RetryPosture

  test "lists the platform retry posture contract in the retry posture packet" do
    assert Contracts.retry_posture_contracts() == ["Platform.RetryPosture.v1"]
  end

  test "builds platform retry posture mirrors for lower integration consumers" do
    assert {:ok, posture} =
             RetryPosture.new(%{
               tenant_ref: "tenant-1",
               installation_ref: "inst-1",
               workspace_ref: "workspace-main",
               project_ref: "project-core",
               environment_ref: "prod",
               system_actor_ref: "system:jido-retry",
               resource_ref: "lower-run:github:123",
               authority_packet_ref: "authz-packet-retry-jido",
               permission_decision_ref: "decision-retry-jido",
               idempotency_key: "retry-posture:jido:github:123",
               trace_id: "trace:m11:085:jido",
               correlation_id: "corr-retry-posture-jido",
               release_manifest_ref: "phase4-v6-milestone11",
               operation_ref: "operation:jido:github:dispatch",
               owner_repo: "jido_integration",
               producer_ref: "Jido.Integration.V2.ControlPlane",
               consumer_ref: "Platform.RetryPosture.v1",
               retry_class: :after_redecision,
               failure_class: "rate_limited",
               max_attempts: 2,
               backoff_policy: %{"strategy" => "exponential", "initial_ms" => 5_000},
               idempotency_scope: "tenant_ref+operation_ref+idempotency_key",
               dead_letter_ref: "dead-letter:jido:github:123",
               safe_action_code: "wait_for_redecision_or_dead_letter",
               retry_after_ms: 5_000,
               operator_message_ref: "operator-message:jido-retry:1"
             })

    assert posture.contract_name == "Platform.RetryPosture.v1"
    assert posture.retry_class == :after_redecision
    assert posture.owner_repo == "jido_integration"
  end

  test "rejects retry posture mirrors without actor, idempotency, or bounded attempts" do
    assert {:error, {:missing_required_fields, fields}} =
             RetryPosture.new(%{
               tenant_ref: "tenant-1",
               installation_ref: "inst-1",
               workspace_ref: "workspace-main",
               project_ref: "project-core",
               environment_ref: "prod",
               resource_ref: "lower-run:github:123",
               authority_packet_ref: "authz-packet-retry-jido",
               permission_decision_ref: "decision-retry-jido",
               trace_id: "trace:m11:085:jido",
               correlation_id: "corr-retry-posture-jido",
               release_manifest_ref: "phase4-v6-milestone11",
               operation_ref: "operation:jido:github:dispatch",
               owner_repo: "jido_integration",
               producer_ref: "Jido.Integration.V2.ControlPlane",
               consumer_ref: "Platform.RetryPosture.v1",
               retry_class: :after_redecision,
               failure_class: "rate_limited",
               max_attempts: 2,
               backoff_policy: %{"strategy" => "exponential"},
               dead_letter_ref: "dead-letter:jido:github:123",
               safe_action_code: "wait_for_redecision_or_dead_letter"
             })

    assert :principal_ref_or_system_actor_ref in fields
    assert :idempotency_key in fields
    assert :idempotency_scope in fields

    assert {:error, :invalid_retry_posture} =
             RetryPosture.new(%{valid_retry_posture() | retry_class: :unsafe_forever})
  end

  defp valid_retry_posture do
    %{
      tenant_ref: "tenant-1",
      installation_ref: "inst-1",
      workspace_ref: "workspace-main",
      project_ref: "project-core",
      environment_ref: "prod",
      system_actor_ref: "system:jido-retry",
      resource_ref: "lower-run:github:123",
      authority_packet_ref: "authz-packet-retry-jido",
      permission_decision_ref: "decision-retry-jido",
      idempotency_key: "retry-posture:jido:github:123",
      trace_id: "trace:m11:085:jido",
      correlation_id: "corr-retry-posture-jido",
      release_manifest_ref: "phase4-v6-milestone11",
      operation_ref: "operation:jido:github:dispatch",
      owner_repo: "jido_integration",
      producer_ref: "Jido.Integration.V2.ControlPlane",
      consumer_ref: "Platform.RetryPosture.v1",
      retry_class: :after_redecision,
      failure_class: "rate_limited",
      max_attempts: 2,
      backoff_policy: %{"strategy" => "exponential"},
      idempotency_scope: "tenant_ref+operation_ref+idempotency_key",
      dead_letter_ref: "dead-letter:jido:github:123",
      safe_action_code: "wait_for_redecision_or_dead_letter"
    }
  end
end
