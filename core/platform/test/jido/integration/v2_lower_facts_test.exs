defmodule Jido.Integration.V2LowerFactsTest do
  use Jido.Integration.V2.Platform.DurableCase

  alias Jido.Integration.V2
  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.AuthorityAuditEnvelope
  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.ExecutionGovernanceProjection
  alias Jido.Integration.V2.ExecutionGovernanceProjection.Compiler
  alias Jido.Integration.V2.InferenceRequest
  alias Jido.Integration.V2.LowerFacts
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.SubmissionIdentity
  alias Jido.Integration.V2.SubstrateReadSlice
  alias Jido.Integration.V2.TenantScope

  defmodule CloudHTTP do
  end

  setup do
    ControlPlane.reset!()

    Req.Test.stub(CloudHTTP, fn conn ->
      Req.Test.json(conn, %{
        "id" => "cmpl_platform_lower_facts_123",
        "model" => "gpt-4o-mini",
        "choices" => [
          %{
            "finish_reason" => "stop",
            "message" => %{
              "role" => "assistant",
              "content" => "Lower facts proof is alive."
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

  test "publishes the frozen lower-facts operation inventory" do
    assert LowerFacts.operations() == [
             :fetch_submission_receipt,
             :fetch_run,
             :attempts,
             :fetch_attempt,
             :events,
             :fetch_artifact,
             :run_artifacts,
             :resolve_trace
           ]

    assert LowerFacts.operation_supported?(:fetch_run)
    assert LowerFacts.operation_supported?(:run_artifacts)
    assert LowerFacts.operation_supported?(:resolve_trace)
    refute LowerFacts.operation_supported?(:review_packet)
    refute LowerFacts.operation_supported?(:derived_state_attachment)
  end

  test "lower-facts boundary requires typed tenant scope" do
    refute function_exported?(LowerFacts, :fetch_run, 1)
    refute function_exported?(SubstrateReadSlice, :fetch_run, 1)

    assert {:error, {:invalid_scope, :typed_tenant_scope_required}} =
             LowerFacts.fetch_run(%{}, "run-platform-lower-facts-missing-scope")

    assert {:error, {:invalid_scope, :typed_tenant_scope_required}} =
             SubstrateReadSlice.fetch_run(%{}, "run-platform-lower-facts-missing-scope")
  end

  test "submission receipt lookup stays stable across duplicate acceptance" do
    invocation = brain_invocation_fixture()
    scope = tenant_scope("tenant-1")
    wrong_scope = tenant_scope("tenant-2")

    assert {:ok, %SubmissionAcceptance{} = first_receipt, _gateway, _runtime_inputs} =
             V2.accept_brain_invocation(
               invocation,
               scope_resolver: __MODULE__.Resolver,
               scope_resolver_opts: [
                 mapping: %{
                   "workspace://tenant-1/root" => "/srv/workspaces/tenant-1"
                 }
               ]
             )

    assert {:ok, %SubmissionAcceptance{} = duplicate_receipt, _gateway, _runtime_inputs} =
             V2.accept_brain_invocation(
               invocation,
               scope_resolver: __MODULE__.Resolver,
               scope_resolver_opts: [
                 mapping: %{
                   "workspace://tenant-1/root" => "/srv/workspaces/tenant-1"
                 }
               ]
             )

    assert duplicate_receipt.status == :duplicate
    assert duplicate_receipt.submission_receipt_ref == first_receipt.submission_receipt_ref

    assert {:ok, fetched_receipt} =
             LowerFacts.fetch_submission_receipt(scope, invocation.submission_key)

    assert fetched_receipt.status == :accepted
    assert fetched_receipt.submission_key == first_receipt.submission_key
    assert fetched_receipt.submission_receipt_ref == first_receipt.submission_receipt_ref
    assert fetched_receipt.ledger_version == first_receipt.ledger_version

    assert {:error, :tenant_mismatch} =
             LowerFacts.fetch_submission_receipt(wrong_scope, invocation.submission_key)
  end

  test "returns the typed generic lower-facts surface without review aggregation" do
    invocation = brain_invocation_fixture()
    submission_scope = tenant_scope("tenant-1")

    lower_scope =
      tenant_scope("tenant-platform-lower-facts-1",
        installation_id: "install-platform-lower-facts-1",
        trace_id: "trace-platform-lower-facts-1"
      )

    wrong_scope = tenant_scope("tenant-platform-lower-facts-2")

    assert {:ok, %SubmissionAcceptance{} = receipt, _gateway, _runtime_inputs} =
             V2.accept_brain_invocation(
               invocation,
               scope_resolver: __MODULE__.Resolver,
               scope_resolver_opts: [
                 mapping: %{
                   "workspace://tenant-1/root" => "/srv/workspaces/tenant-1"
                 }
               ]
             )

    assert {:ok, fetched_receipt} =
             LowerFacts.fetch_submission_receipt(submission_scope, invocation.submission_key)

    assert receipt.status in [:accepted, :duplicate]
    assert fetched_receipt.submission_key == receipt.submission_key
    assert fetched_receipt.submission_receipt_ref == receipt.submission_receipt_ref
    assert fetched_receipt.status == :accepted
    assert fetched_receipt.ledger_version == receipt.ledger_version

    request =
      InferenceRequest.new!(%{
        request_id: "req-platform-lower-facts-1",
        operation: :generate_text,
        messages: [%{role: "user", content: "Summarize the lower facts seam"}],
        prompt: nil,
        model_preference: %{provider: "openai", id: "gpt-4o-mini"},
        target_preference: %{target_class: "cloud_provider"},
        stream?: false,
        tool_policy: %{},
        output_constraints: %{},
        metadata: %{
          tenant_id: "tenant-platform-lower-facts-1",
          installation_id: "install-platform-lower-facts-1",
          trace_id: "trace-platform-lower-facts-1"
        }
      })

    assert {:ok, result} =
             V2.invoke_inference(
               request,
               api_key: "cloud-fixture-token",
               req_http_options: [plug: {Req.Test, CloudHTTP}],
               run_id: "run-platform-lower-facts-1",
               decision_ref: "decision-platform-lower-facts-1",
               trace_id: "trace-platform-lower-facts-1"
             )

    artifact = artifact_fixture(result.run.run_id, result.attempt.attempt_id)
    assert :ok = V2.record_artifact(artifact)

    assert {:ok, stored_run} = LowerFacts.fetch_run(lower_scope, result.run.run_id)
    assert stored_run.run_id == result.run.run_id
    assert stored_run.capability_id == "inference.execute"

    assert {:ok, [stored_attempt]} = LowerFacts.attempts(lower_scope, result.run.run_id)
    assert stored_attempt.attempt_id == result.attempt.attempt_id

    assert {:ok, fetched_attempt} =
             LowerFacts.fetch_attempt(lower_scope, result.attempt.attempt_id)

    assert fetched_attempt.attempt_id == result.attempt.attempt_id
    assert fetched_attempt.output["inference_result"]["status"] == "ok"

    assert {:ok, events} = LowerFacts.events(lower_scope, result.run.run_id)
    assert {:ok, ^events} = LowerFacts.events(lower_scope, result.attempt.attempt_id)

    assert Enum.map(events, & &1.type) == [
             "inference.request_admitted",
             "inference.attempt_started",
             "inference.compatibility_evaluated",
             "inference.target_resolved",
             "inference.attempt_completed"
           ]

    assert {:ok, stored_artifact} = LowerFacts.fetch_artifact(lower_scope, artifact.artifact_id)
    assert stored_artifact == artifact
    assert {:ok, [^artifact]} = LowerFacts.run_artifacts(lower_scope, result.run.run_id)

    assert {:ok, trace_resolution} = LowerFacts.resolve_trace(lower_scope, result.run.run_id)
    assert trace_resolution.run.run_id == result.run.run_id
    assert Enum.map(trace_resolution.attempts, & &1.attempt_id) == [result.attempt.attempt_id]
    assert Enum.map(trace_resolution.artifacts, & &1.artifact_id) == [artifact.artifact_id]

    assert {:error, :tenant_mismatch} = LowerFacts.fetch_run(wrong_scope, result.run.run_id)
    assert {:error, :tenant_mismatch} = LowerFacts.attempts(wrong_scope, result.run.run_id)

    assert {:error, :tenant_mismatch} =
             LowerFacts.fetch_attempt(wrong_scope, result.attempt.attempt_id)

    assert {:error, :tenant_mismatch} = LowerFacts.events(wrong_scope, result.run.run_id)

    assert {:error, :tenant_mismatch} =
             LowerFacts.fetch_artifact(wrong_scope, artifact.artifact_id)

    assert {:error, :tenant_mismatch} = LowerFacts.run_artifacts(wrong_scope, result.run.run_id)
    assert {:error, :tenant_mismatch} = LowerFacts.resolve_trace(wrong_scope, result.run.run_id)
  end

  defp tenant_scope(tenant_id, attrs \\ []) do
    attrs
    |> Keyword.merge(
      tenant_id: tenant_id,
      actor_ref: %{id: "actor-lower-facts-test", kind: "test"},
      authorized_at: DateTime.utc_now()
    )
    |> TenantScope.new!()
  end

  defmodule Resolver do
    @behaviour Jido.Integration.V2.BrainIngress.ScopeResolver

    def resolve(logical_workspace_ref, file_scope_ref, opts) do
      mapping = Keyword.get(opts, :mapping, %{})

      with {:ok, workspace_root} <- fetch(mapping, logical_workspace_ref),
           {:ok, file_scope} <- fetch(mapping, file_scope_ref) do
        {:ok, %{workspace_root: workspace_root, file_scope: file_scope}}
      end
    end

    defp fetch(_mapping, nil), do: {:ok, nil}

    defp fetch(mapping, value) do
      case Map.fetch(mapping, value) do
        {:ok, resolved} -> {:ok, resolved}
        :error -> {:error, {:scope_unresolvable, value}}
      end
    end
  end

  defp artifact_fixture(run_id, attempt_id) do
    checksum = "sha256:" <> String.duplicate("c", 64)

    ArtifactRef.new!(%{
      artifact_id: "artifact-platform-lower-facts-1",
      run_id: run_id,
      attempt_id: attempt_id,
      artifact_type: :tool_output,
      transport_mode: :object_store,
      checksum: checksum,
      size_bytes: 64,
      payload_ref: %{
        store: "s3",
        key: "lower-facts/#{run_id}/#{attempt_id}",
        ttl_s: 86_400,
        access_control: :run_scoped,
        checksum: checksum,
        size_bytes: 64
      },
      retention_class: "review_output",
      redaction_status: :clear,
      metadata: %{
        surface: "lower_facts",
        producer: "platform_test"
      }
    })
  end

  defp brain_invocation_fixture do
    token = Integer.to_string(System.unique_integer([:positive]))

    identity =
      SubmissionIdentity.new!(%{
        submission_family: :invocation,
        tenant_id: "tenant-1",
        session_id: "session-#{token}",
        request_id: "request-#{token}",
        invocation_request_id: "invoke-#{token}",
        causal_group_id: "cg-#{token}",
        target_id: "target-#{token}",
        target_kind: "cli",
        selected_step_id: "step-#{token}",
        authority_decision_id: "decision-#{token}",
        execution_governance_id: "governance-#{token}",
        execution_intent_family: "process"
      })

    authority_payload =
      AuthorityAuditEnvelope.new!(%{
        contract_version: "v1",
        decision_id: "decision-#{token}",
        tenant_id: "tenant-1",
        request_id: "request-#{token}",
        policy_version: "policy-7",
        boundary_class: "hazmat",
        trust_profile: "trusted_operator",
        approval_profile: "manual",
        egress_profile: "restricted",
        workspace_profile: "workspace_attached",
        resource_profile: "balanced",
        decision_hash: String.duplicate("f", 64),
        extensions: %{}
      })

    governance_payload =
      ExecutionGovernanceProjection.new!(%{
        contract_version: "v1",
        execution_governance_id: "governance-#{token}",
        authority_ref: %{
          "decision_id" => "decision-#{token}",
          "policy_version" => "policy-7",
          "decision_hash" => String.duplicate("f", 64)
        },
        sandbox: %{
          "level" => "strict",
          "egress" => "restricted",
          "approvals" => "manual",
          "acceptable_attestation" => ["local-erlexec-weak"],
          "allowed_tools" => ["bash", "git"],
          "file_scope_ref" => "workspace://tenant-1/root",
          "file_scope_hint" => "/srv/workspaces/tenant-1"
        },
        boundary: %{
          "boundary_class" => "hazmat",
          "trust_profile" => "trusted_operator",
          "requested_attach_mode" => "attach_if_exists",
          "requested_ttl_ms" => 60_000
        },
        topology: %{
          "topology_intent_id" => "topology-#{token}",
          "session_mode" => "attached",
          "coordination_mode" => "single_target",
          "topology_epoch" => 9,
          "routing_hints" => %{
            "runtime_driver" => "asm",
            "runtime_provider" => "codex"
          }
        },
        workspace: %{
          "workspace_profile" => "workspace_attached",
          "logical_workspace_ref" => "workspace://tenant-1/root",
          "mutability" => "read_write"
        },
        resources: %{
          "resource_profile" => "balanced",
          "cpu_class" => "medium",
          "memory_class" => "medium",
          "wall_clock_budget_ms" => 300_000
        },
        placement: %{
          "execution_family" => "process",
          "placement_intent" => "host_local",
          "target_kind" => "cli",
          "node_affinity" => "same_node"
        },
        operations: %{
          "allowed_operations" => ["shell.exec"],
          "effect_classes" => ["filesystem", "process"]
        }
      })

    compiled_projection = Compiler.compile!(governance_payload)

    BrainInvocation.new!(%{
      submission_identity: identity,
      request_id: "request-#{token}",
      session_id: "session-#{token}",
      tenant_id: "tenant-1",
      trace_id: "trace-#{token}",
      actor_id: "actor-1",
      target_id: "target-#{token}",
      target_kind: "cli",
      runtime_class: :direct,
      allowed_operations: ["shell.exec"],
      authority_payload: authority_payload,
      execution_governance_payload: governance_payload,
      gateway_request: compiled_projection.gateway_request,
      runtime_request: compiled_projection.runtime_request,
      boundary_request: compiled_projection.boundary_request,
      execution_intent_family: "process",
      execution_intent: %{"argv" => ["echo", "hello"]},
      extensions: %{"submission_dedupe_key" => "dedupe-#{token}"}
    })
  end
end
