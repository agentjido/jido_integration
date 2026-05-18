defmodule Jido.Integration.V2.RuntimeRouter.ExecutionPlaneTreAdapterTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.GovernedLowerEnvelope
  alias Jido.Integration.V2.GovernedLowerReceipt
  alias Jido.Integration.V2.RuntimeRouter.ExecutionPlaneTreAdapter

  setup do
    tmp_root =
      Path.join(
        System.tmp_dir!(),
        "jido-execution-plane-tre-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_root)

    runner_path = Path.join(tmp_root, "fake-rex-runner")
    File.write!(runner_path, fake_runner_script())
    File.chmod!(runner_path, 0o755)

    on_exit(fn -> File.rm_rf(tmp_root) end)

    {:ok, runner_path: runner_path}
  end

  test "executes a governed TRE envelope through ExecutionPlane and returns receipts", %{
    runner_path: runner_path
  } do
    envelope = governed_tre_envelope(read_only_script())
    capability = tre_capability()

    assert {:ok, result} =
             ExecutionPlaneTreAdapter.execute(capability, %{"value" => "ok"}, %{
               run_id: "run-1",
               attempt_id: "attempt-1",
               opts: %{
                 governed_lower_envelope: envelope,
                 tre_runner_path: runner_path,
                 tre_materializer: materializer(read_only_script(), read_only_policy())
               }
             })

    assert result.output.adapter == :execution_plane_tre
    assert result.output.lower_runtime_kind == :tre_rhai
    assert result.output.execution_plane_receipt["status"] == "succeeded"
    assert result.output.execution_plane_receipt["runner_output"]["output"] == "jido-tre-ok"

    receipt = GovernedLowerReceipt.new!(result.output.governed_lower_receipt)
    assert receipt.lower_runtime_kind == :tre_rhai
    assert receipt.status == :succeeded
    assert receipt.tenant_ref == envelope.tenant_ref
    assert receipt.policy_bundle_ref == envelope.policy_bundle_ref
    assert receipt.script_hash == envelope.script_hash
    assert receipt.artifact_refs == ["tre-artifact://trace-jido-tre/runner-output"]
    refute String.contains?(inspect(result.output.governed_lower_receipt), "access_token")
    refute String.contains?(inspect(result.output.governed_lower_receipt), "api_key")
    refute String.contains?(inspect(result.output.governed_lower_receipt), "secret")
    assert GovernedLowerReceipt.matches_envelope?(receipt, envelope)

    assert Enum.any?(result.events, &(&1.type == "tre.execution_plane.completed"))
  end

  defp tre_capability do
    Capability.new!(%{
      id: "test.tre.execute",
      connector: "tre_test",
      runtime_class: :direct,
      kind: :operation,
      transport_profile: :action,
      handler: __MODULE__,
      metadata: %{lower_runtime_kinds: [:tre_rhai]}
    })
  end

  defp governed_tre_envelope(script_source) do
    GovernedLowerEnvelope.new!(%{
      lower_request_ref: "lower-request://jido-tre",
      lower_runtime_kind: :tre_rhai,
      runtime_profile_ref: "runtime-profile://tre/local",
      runtime_profile_kind: :tre_rhai,
      capability_id: "test.tre.execute",
      action_id: "test.tre.execute",
      tenant_ref: "tenant-1",
      subject_ref: "subject-1",
      run_ref: "run-1",
      workflow_ref: "workflow-1",
      attempt_ref: "attempt-1",
      trace_id: "trace-jido-tre",
      idempotency_key: "idem-jido-tre",
      authority_ref: "authority://jido-tre",
      authority_decision_hash:
        "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allowed_operations: ["test.tre.execute"],
      policy_profile_ref: "tre-policy-profile://coding-ops/standard",
      policy_bundle_ref: "tre-policy-bundle://coding-ops/phase14",
      policy_bundle_hash:
        "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      cedar_schema_ref: "cedar-schema://nshkr_tre/coding_ops/v1",
      cedar_schema_hash:
        "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      script_ref: "script:tre:jido-read-only:v1",
      script_hash: sha256(script_source),
      script_api_version: "nshkr.tre.rhai.v1",
      declared_actions: ["fs.read"],
      resource_scope_refs: ["workspace://jido-tre"],
      workspace_ref: "workspace://jido-tre",
      target_ref: "target://local",
      sandbox_profile_ref: "sandbox://tre/local",
      sandbox_level: :strict,
      acceptable_attestation: ["attestation://local/dev"],
      input_ref: "input://jido-tre",
      input_hash: sha256("jido-tre-input")
    })
  end

  defp materializer(script_source, policy_source) do
    fn _envelope ->
      {:ok,
       %{
         script_source: script_source,
         policy_source: policy_source,
         script_arguments: %{
           "file_path" => %{"stringValue" => "README.md"}
         }
       }}
    end
  end

  defp read_only_script do
    ~s|let contents = cat(file_path); contents|
  end

  defp read_only_policy do
    """
    permit(principal, action, resource)
    when { action == file_system::Action::"read" };
    """
  end

  defp fake_runner_script do
    """
    #!/bin/sh
    set -eu
    script_file=""
    policy_file=""
    args_file=""

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --script-file|-s)
          script_file="$2"
          shift 2
          ;;
        --policy-file|-p)
          policy_file="$2"
          shift 2
          ;;
        --script-arguments-file|-a)
          args_file="$2"
          shift 2
          ;;
        --output-format|-o)
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done

    if [ ! -f "$script_file" ] || [ ! -f "$policy_file" ] || [ ! -f "$args_file" ]; then
      printf '{"output":"","status":"ERROR","error":{"error_type":"VALIDATION_EXCEPTION","message":"missing runner input file"}}'
      exit 0
    fi

    printf '{"output":"jido-tre-ok","status":"SUCCESS"}'
    """
  end

  defp sha256(value) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, value), case: :lower)
  end
end
