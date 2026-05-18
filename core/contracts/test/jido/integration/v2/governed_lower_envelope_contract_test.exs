defmodule Jido.Integration.V2.GovernedLowerEnvelopeContractTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.{
    GovernedLowerDenial,
    GovernedLowerEnvelope,
    GovernedLowerReceipt
  }

  @base_attrs %{
    lower_request_ref: "lower_req_1",
    lower_runtime_kind: :deterministic_fixture,
    runtime_profile_ref: "runtime_profile_local",
    runtime_profile_kind: :temporal_local,
    capability_id: "codex.session.turn",
    action_id: "codex.session.turn",
    tenant_ref: "tenant_1",
    subject_ref: "subject_1",
    run_ref: "run_1",
    workflow_ref: "workflow_1",
    attempt_ref: "attempt_1",
    trace_id: "trace_1",
    idempotency_key: "idem_1",
    authority_ref: "authority_1",
    authority_decision_hash:
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allowed_operations: ["codex.session.turn"],
    connector_ref: "jido/connectors/codex_cli",
    connector_manifest_ref: "manifest_1",
    connector_manifest_hash:
      "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    connector_manifest_state: :active,
    capability_negotiation_ref: "cap_neg_1",
    policy_bundle_ref: "policy_bundle_1",
    policy_bundle_hash: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    cedar_schema_ref: "cedar_schema_1",
    cedar_schema_hash: "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    script_ref: "script_1",
    script_hash: "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    script_api_version: "rhai-1",
    declared_actions: ["codex.session.turn"],
    package_refs: ["package_1"],
    resource_scope_refs: ["workspace_1"],
    workspace_ref: "workspace_1",
    target_ref: "target_1",
    placement_ref: "node_1",
    sandbox_profile_ref: "sandbox_profile_1",
    sandbox_level: :process,
    network_policy_ref: "network_policy_1",
    filesystem_policy_ref: "filesystem_policy_1",
    acceptable_attestation: ["attestation_1"],
    attestation_requirement_ref: "attestation_requirement_1",
    evidence_profile_ref: "evidence_profile_1",
    redaction_profile_ref: "redaction_profile_1",
    input_ref: "input_1",
    input_hash: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  }

  test "normalizes MVP lower runtime kinds and keeps them distinct from backend runtime_kind" do
    envelope = GovernedLowerEnvelope.new!(@base_attrs)
    encoded = Jason.encode!(GovernedLowerEnvelope.to_map(envelope))
    decoded = Jason.decode!(encoded)

    assert envelope.lower_runtime_kind == :deterministic_fixture
    assert envelope.capability_id == "codex.session.turn"
    assert envelope.action_id == "codex.session.turn"
    assert envelope.allowed_operations == ["codex.session.turn"]
    refute Map.has_key?(Map.from_struct(envelope), :runtime_kind)
    refute Map.has_key?(decoded, "runtime_kind")
    assert decoded["contract_name"] == GovernedLowerEnvelope.contract_name()
    assert decoded["lower_runtime_kind"] == "deterministic_fixture"
    assert decoded["runtime_profile_kind"] == "temporal_local"
    assert decoded["package_refs"] == ["package_1"]
    assert decoded["attestation_requirement_ref"] == "attestation_requirement_1"
  end

  test "accepts reserved TRE runtime kind but marks it non-dispatchable" do
    envelope =
      @base_attrs
      |> Map.put(:lower_runtime_kind, "tre_rhai")
      |> Map.put(:policy_bundle_ref, "cedar_policy_bundle_1")
      |> Map.put(
        :policy_bundle_hash,
        "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
      )
      |> Map.put(:cedar_schema_ref, "cedar_schema_1")
      |> Map.put(
        :cedar_schema_hash,
        "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
      )
      |> Map.put(:script_ref, "rhai_script_1")
      |> Map.put(
        :script_hash,
        "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      )
      |> GovernedLowerEnvelope.new!()

    assert envelope.lower_runtime_kind == :tre_rhai
    refute GovernedLowerEnvelope.dispatchable?(envelope)

    encoded = Jason.encode!(GovernedLowerEnvelope.to_map(envelope))

    assert %{"lower_runtime_kind" => "tre_rhai", "policy_bundle_ref" => "cedar_policy_bundle_1"} =
             Jason.decode!(encoded)
  end

  test "serializes all MVP lower runtime kinds" do
    for lower_runtime_kind <- [:deterministic_fixture, :codex_session, :direct_connector] do
      expected_lower_runtime_kind = Atom.to_string(lower_runtime_kind)

      envelope =
        @base_attrs
        |> Map.put(:lower_runtime_kind, lower_runtime_kind)
        |> GovernedLowerEnvelope.new!()

      assert GovernedLowerEnvelope.dispatchable?(envelope)

      assert %{
               "lower_runtime_kind" => ^expected_lower_runtime_kind,
               "capability_id" => "codex.session.turn"
             } = envelope |> GovernedLowerEnvelope.to_map() |> Jason.encode!() |> Jason.decode!()
    end
  end

  test "accepts Citadel sandbox posture levels in the governed lower envelope" do
    for sandbox_level <- [:strict, :standard, :none, :process, :container, :microvm] do
      envelope =
        @base_attrs
        |> Map.put(:sandbox_level, sandbox_level)
        |> GovernedLowerEnvelope.new!()

      assert envelope.sandbox_level == sandbox_level
    end
  end

  test "rejects unknown lower runtime kinds and ungranted capabilities" do
    error =
      assert_raise ArgumentError, fn ->
        GovernedLowerEnvelope.new!(Map.put(@base_attrs, :lower_runtime_kind, :custom_tunnel))
      end

    assert String.contains?(Exception.message(error), "invalid lower_runtime_kind")

    error =
      assert_raise ArgumentError, fn ->
        GovernedLowerEnvelope.new!(
          Map.put(@base_attrs, :allowed_operations, ["linear.comments.update"])
        )
      end

    assert String.contains?(
             Exception.message(error),
             "allowed_operations must include capability_id"
           )
  end

  test "requires active manifest for non-idempotent write negotiation" do
    error =
      assert_raise ArgumentError, fn ->
        @base_attrs
        |> Map.put(:capability_id, "linear.comments.update")
        |> Map.put(:action_id, "linear.comments.update")
        |> Map.put(:allowed_operations, ["linear.comments.update"])
        |> Map.put(:side_effect_class, :write)
        |> Map.put(:idempotency_class, :non_idempotent)
        |> Map.put(:connector_manifest_state, :stale)
        |> GovernedLowerEnvelope.new!()
      end

    assert String.contains?(Exception.message(error), "active connector manifest")
  end

  test "receipt and denial join back to the envelope" do
    envelope = GovernedLowerEnvelope.new!(@base_attrs)

    receipt =
      GovernedLowerReceipt.new!(%{
        lower_receipt_ref: "lower_receipt_1",
        lower_request_ref: envelope.lower_request_ref,
        lower_runtime_kind: envelope.lower_runtime_kind,
        status: :succeeded,
        tenant_ref: envelope.tenant_ref,
        subject_ref: envelope.subject_ref,
        run_ref: envelope.run_ref,
        workflow_ref: envelope.workflow_ref,
        attempt_ref: envelope.attempt_ref,
        trace_id: envelope.trace_id,
        idempotency_key: envelope.idempotency_key,
        authority_ref: envelope.authority_ref,
        authority_decision_hash: envelope.authority_decision_hash,
        capability_id: envelope.capability_id,
        action_id: envelope.action_id,
        connector_ref: envelope.connector_ref,
        connector_manifest_ref: envelope.connector_manifest_ref,
        connector_manifest_hash: envelope.connector_manifest_hash,
        connector_manifest_state: envelope.connector_manifest_state,
        capability_negotiation_ref: envelope.capability_negotiation_ref,
        policy_bundle_ref: envelope.policy_bundle_ref,
        policy_bundle_hash: envelope.policy_bundle_hash,
        cedar_schema_ref: envelope.cedar_schema_ref,
        cedar_schema_hash: envelope.cedar_schema_hash,
        script_ref: envelope.script_ref,
        script_hash: envelope.script_hash,
        script_api_version: envelope.script_api_version,
        declared_actions: envelope.declared_actions,
        package_refs: envelope.package_refs,
        resource_scope_refs: envelope.resource_scope_refs,
        sandbox_profile_ref: envelope.sandbox_profile_ref,
        sandbox_level: envelope.sandbox_level,
        network_policy_ref: envelope.network_policy_ref,
        filesystem_policy_ref: envelope.filesystem_policy_ref,
        acceptable_attestation: envelope.acceptable_attestation,
        attestation_requirement_ref: envelope.attestation_requirement_ref
      })

    assert GovernedLowerReceipt.matches_envelope?(receipt, envelope)

    assert %{
             "contract_name" => "JidoIntegration.GovernedLowerReceipt.v1",
             "lower_runtime_kind" => "deterministic_fixture",
             "status" => "succeeded",
             "policy_bundle_ref" => "policy_bundle_1",
             "script_ref" => "script_1",
             "package_refs" => ["package_1"],
             "sandbox_profile_ref" => "sandbox_profile_1",
             "acceptable_attestation" => ["attestation_1"],
             "attestation_requirement_ref" => "attestation_requirement_1"
           } = receipt |> GovernedLowerReceipt.to_map() |> Jason.encode!() |> Jason.decode!()

    denial =
      GovernedLowerDenial.new!(%{
        lower_denial_ref: "lower_denial_1",
        lower_request_ref: envelope.lower_request_ref,
        lower_runtime_kind: envelope.lower_runtime_kind,
        denial_class: :capability_denied,
        reason: "missing allowed operation",
        tenant_ref: envelope.tenant_ref,
        run_ref: envelope.run_ref,
        trace_id: envelope.trace_id,
        authority_ref: envelope.authority_ref,
        authority_decision_hash: envelope.authority_decision_hash,
        capability_id: envelope.capability_id,
        connector_manifest_ref: envelope.connector_manifest_ref,
        capability_negotiation_ref: envelope.capability_negotiation_ref
      })

    assert GovernedLowerDenial.matches_envelope?(denial, envelope)

    assert %{
             "contract_name" => "JidoIntegration.GovernedLowerDenial.v1",
             "lower_runtime_kind" => "deterministic_fixture",
             "denial_class" => "capability_denied"
           } = denial |> GovernedLowerDenial.to_map() |> Jason.encode!() |> Jason.decode!()
  end

  test "lower receipts require tenant scope and reject raw credential extensions" do
    envelope = GovernedLowerEnvelope.new!(@base_attrs)

    missing_tenant_error =
      assert_raise ArgumentError, fn ->
        receipt_attrs(envelope)
        |> Map.delete(:tenant_ref)
        |> GovernedLowerReceipt.new!()
      end

    assert String.contains?(Exception.message(missing_tenant_error), "tenant_ref")

    raw_secret_error =
      assert_raise ArgumentError, fn ->
        envelope
        |> receipt_attrs()
        |> Map.put(:extensions, %{"runtime" => %{"access_token" => "secret-token"}})
        |> GovernedLowerReceipt.new!()
      end

    assert String.contains?(Exception.message(raw_secret_error), "raw credential material")
  end

  test "lower denial taxonomy covers authority, manifest, resource, sandbox, attestation, runtime, receipt, and retry classes" do
    envelope = GovernedLowerEnvelope.new!(@base_attrs)

    for denial_class <- [
          :authority_denied,
          :capability_denied,
          :manifest_missing,
          :manifest_stale,
          :manifest_invalid,
          :manifest_quarantined,
          :runtime_profile_incompatible,
          :resource_scope_unresolvable,
          :sandbox_downgrade,
          :attestation_unsatisfied,
          :policy_bundle_missing,
          :script_binding_invalid,
          :cedar_policy_denied,
          :lower_runtime_unavailable,
          :lower_runtime_failed,
          :receipt_missing,
          :retry_not_safe
        ] do
      denial =
        GovernedLowerDenial.new!(%{
          lower_denial_ref: "lower_denial_#{denial_class}",
          lower_request_ref: envelope.lower_request_ref,
          lower_runtime_kind: envelope.lower_runtime_kind,
          denial_class: denial_class,
          reason: Atom.to_string(denial_class),
          tenant_ref: envelope.tenant_ref,
          run_ref: envelope.run_ref,
          trace_id: envelope.trace_id,
          authority_ref: envelope.authority_ref,
          authority_decision_hash: envelope.authority_decision_hash,
          capability_id: envelope.capability_id
        })

      assert denial.denial_class == denial_class
      assert GovernedLowerDenial.matches_envelope?(denial, envelope)
    end
  end

  defp receipt_attrs(envelope) do
    %{
      lower_receipt_ref: "lower_receipt_1",
      lower_request_ref: envelope.lower_request_ref,
      lower_runtime_kind: envelope.lower_runtime_kind,
      status: :succeeded,
      tenant_ref: envelope.tenant_ref,
      subject_ref: envelope.subject_ref,
      run_ref: envelope.run_ref,
      workflow_ref: envelope.workflow_ref,
      attempt_ref: envelope.attempt_ref,
      trace_id: envelope.trace_id,
      idempotency_key: envelope.idempotency_key,
      authority_ref: envelope.authority_ref,
      authority_decision_hash: envelope.authority_decision_hash,
      capability_id: envelope.capability_id,
      action_id: envelope.action_id
    }
  end
end
