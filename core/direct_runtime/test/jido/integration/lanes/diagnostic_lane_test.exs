defmodule Jido.Integration.Lanes.DiagnosticLaneTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Lanes.{DiagnosticLane, LowerEffectReceipt}
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.DirectRuntime
  alias Jido.Integration.V2.GovernedLowerEnvelope
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.ManifestRegistry
  alias Jido.Integration.V2.Manifests

  test "diagnostic manifest registers through the generic connector registry" do
    manifest = DiagnosticLane.manifest()
    entry = manifest_entry(manifest)

    assert manifest.connector == "diagnostic_lane"
    assert manifest.runtime_families == [:direct]

    assert Enum.sort(Enum.map(manifest.operations, & &1.operation_id)) ==
             Enum.sort(DiagnosticLane.operation_ids())

    manifest_dump = manifest |> Manifest.dump() |> inspect() |> String.downcase()

    for forbidden <- ["github", "linear", "codex"] do
      refute String.contains?(manifest_dump, forbidden)
    end

    assert {:ok, ^entry} =
             Manifests.fetch_connector_manifest(DiagnosticLane.connector_ref(),
               manifest_entries: [entry]
             )

    assert {:ok, _manifest, operation} =
             Manifests.fetch_operation(
               DiagnosticLane.connector_ref(),
               "diagnostic.echo",
               manifest_entries: [entry]
             )

    assert operation.runtime_class == :direct
  end

  test "diagnostic manifest resolves to a direct resource-effect operation descriptor" do
    manifest = DiagnosticLane.manifest()
    entry = manifest_entry(manifest)

    assert {:ok, descriptor} =
             Manifests.resolve_operation(lookup_request("diagnostic.echo", entry),
               manifest_entries: [entry]
             )

    assert descriptor.operation_ref == "diagnostic.echo"
    assert descriptor.operation_class == :resource_effect
    assert descriptor.binding_kind == :resource_effect
    assert descriptor.runtime_family == :direct
  end

  test "direct runtime routes diagnostic execution to Execution Plane and returns lower effect receipt" do
    capability = capability!("diagnostic.echo")
    envelope = governed_envelope("diagnostic.echo")

    assert {:ok, result} =
             DirectRuntime.execute(
               capability,
               %{"message" => "hello"},
               %{governed_lower_envelope: envelope}
             )

    receipt = result.output["lower_effect_receipt"]

    assert receipt["effect_ref"] == envelope.effect_ref
    assert receipt["status"] == "success"
    assert receipt["lower_facts"]["diagnostic_result"]["payload"]["message"] == "hello"
    assert receipt["trace_ref"] == envelope.trace_id
    assert [evidence_ref] = receipt["evidence_refs"]
    assert String.contains?(evidence_ref, "aitrace://")

    assert {:ok, %LowerEffectReceipt{}} = LowerEffectReceipt.new(receipt)
  end

  test "governed effect envelope is validated before dispatch" do
    capability = capability!("diagnostic.echo")

    envelope =
      governed_envelope("diagnostic.echo") |> Map.from_struct() |> Map.delete(:effect_ref)

    assert {:error, :effect_ref_required, result} =
             DirectRuntime.execute(
               capability,
               %{"message" => "hello"},
               %{governed_lower_envelope: envelope}
             )

    assert result.output["reason"] == "effect_ref_required"
  end

  test "diagnostic execution exports redacted AITrace evidence refs" do
    capability = capability!("diagnostic.system_info")
    envelope = governed_envelope("diagnostic.system_info")

    assert {:ok, result} =
             DirectRuntime.execute(
               capability,
               %{"access_token" => "secret", "ignored" => "value"},
               %{governed_lower_envelope: envelope}
             )

    evidence = result.output["aitrace_evidence"]

    assert evidence["effect_ref"] == envelope.effect_ref
    assert evidence["authority_ref"] == envelope.authority_ref
    assert evidence["receipt_ref"] == result.output["lower_effect_receipt"]["receipt_ref"]
    refute String.contains?(inspect(evidence), "secret")
    refute String.contains?(inspect(result.output["lower_effect_receipt"]), "secret")
  end

  defp capability!(operation_id) do
    manifest = DiagnosticLane.manifest()
    operation = Manifest.fetch_operation(manifest, operation_id)
    Capability.from_operation!(manifest.connector, operation)
  end

  defp manifest_entry(manifest) do
    ManifestRegistry.Entry.new!(
      connector_ref: DiagnosticLane.connector_ref(),
      manifest_ref: DiagnosticLane.manifest_ref(),
      manifest: manifest,
      provider_family: "generic",
      adapter_ref: "adapter://jido/diagnostic_lane"
    )
  end

  defp lookup_request(operation_id, entry) do
    %{
      connector_ref: entry.connector_ref,
      manifest_ref: entry.manifest_ref,
      operation_ref: operation_id,
      operation_role: :resource_effect,
      operation_class: :resource_effect,
      binding_kind: :resource_effect,
      required_runtime_family: :direct,
      binding_ref: "binding://diagnostic/default",
      pack_ref: "pack://diagnostic/default",
      pack_revision: "1",
      credential_scope_ref: "credential-scope://none",
      compiled_manifest_hash: entry.manifest_digest
    }
  end

  defp governed_envelope(capability_id) do
    GovernedLowerEnvelope.new!(%{
      lower_request_ref: "lower-request://diagnostic/001",
      lower_runtime_kind: :direct_connector,
      runtime_profile_ref: "runtime-profile://diagnostic/direct",
      runtime_profile_kind: :diagnostic,
      capability_id: capability_id,
      action_id: capability_id,
      tenant_ref: "tenant://diagnostic",
      run_ref: "run://diagnostic/001",
      trace_id: "trace://diagnostic/001",
      idempotency_key: "diagnostic-001",
      authority_ref: "authority://diagnostic/001",
      authority_decision_hash:
        "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      allowed_operations: [capability_id],
      connector_ref: DiagnosticLane.connector_ref(),
      connector_manifest_ref: DiagnosticLane.manifest_ref(),
      connector_manifest_hash: DiagnosticLane.manifest_hash(),
      connector_manifest_state: :active,
      side_effect_class: :read,
      idempotency_class: :idempotent,
      runtime_class: :direct,
      effect_ref: "effect://diagnostic/001",
      expected_version: 1,
      compensation_posture: :not_required,
      evidence_profile_ref: "evidence-profile://governed-effect",
      redaction_profile_ref: "redaction-profile://standard"
    })
  end
end
