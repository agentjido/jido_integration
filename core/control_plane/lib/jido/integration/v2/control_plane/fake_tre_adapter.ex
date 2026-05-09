defmodule Jido.Integration.V2.ControlPlane.FakeTreAdapter do
  @moduledoc """
  Deterministic fake adapter for the reserved `:tre_rhai` governed lower lane.

  This adapter proves the TRE contract shape without invoking Cedar, Rhai, or a
  runner. It consumes the governed lower envelope selected by Citadel/Jido
  admission and returns a terminal governed lower receipt in the runtime output.
  """

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.GovernedLowerEnvelope
  alias Jido.Integration.V2.GovernedLowerReceipt
  alias Jido.Integration.V2.RuntimeResult

  @receipt_copy_fields [
    :lower_request_ref,
    :lower_runtime_kind,
    :runtime_profile_ref,
    :runtime_profile_kind,
    :tenant_ref,
    :subject_ref,
    :run_ref,
    :workflow_ref,
    :attempt_ref,
    :trace_id,
    :idempotency_key,
    :authority_ref,
    :authority_decision_hash,
    :allowed_operations,
    :capability_id,
    :action_id,
    :connector_ref,
    :connector_manifest_ref,
    :connector_manifest_hash,
    :connector_manifest_state,
    :capability_negotiation_ref,
    :policy_profile_ref,
    :policy_bundle_ref,
    :policy_bundle_hash,
    :cedar_schema_ref,
    :cedar_schema_hash,
    :script_ref,
    :script_hash,
    :script_api_version,
    :declared_actions,
    :package_refs,
    :resource_scope_refs,
    :workspace_ref,
    :target_ref,
    :placement_ref,
    :sandbox_profile_ref,
    :sandbox_level,
    :network_policy_ref,
    :filesystem_policy_ref,
    :acceptable_attestation,
    :attestation_requirement_ref,
    :evidence_profile_ref,
    :redaction_profile_ref,
    :input_ref,
    :input_hash
  ]

  @spec execute(Capability.t(), map(), map()) ::
          {:ok, RuntimeResult.t()} | {:error, term(), RuntimeResult.t()}
  def execute(%Capability{} = capability, input, context)
      when is_map(input) and is_map(context) do
    case governed_lower_envelope(context) do
      %GovernedLowerEnvelope{lower_runtime_kind: :tre_rhai} = envelope ->
        receipt = governed_lower_receipt!(envelope, context)

        {:ok,
         RuntimeResult.new!(%{
           output: %{
             adapter: :fake_tre,
             capability_id: capability.id,
             lower_request_ref: envelope.lower_request_ref,
             lower_runtime_kind: envelope.lower_runtime_kind,
             runtime_profile_ref: envelope.runtime_profile_ref,
             resource_scope_refs: envelope.resource_scope_refs,
             governed_lower_receipt: GovernedLowerReceipt.to_map(receipt)
           },
           runtime_ref_id: "tre-fake://#{URI.encode_www_form(envelope.lower_request_ref)}",
           events: [
             %{
               type: "tre.fake.started",
               stream: :control,
               payload: %{
                 adapter: "fake_tre",
                 capability_id: capability.id,
                 lower_request_ref: envelope.lower_request_ref
               }
             },
             %{
               type: "tre.fake.completed",
               stream: :control,
               payload: %{
                 lower_receipt_ref: receipt.lower_receipt_ref,
                 lower_request_ref: envelope.lower_request_ref,
                 lower_runtime_kind: "tre_rhai"
               }
             }
           ],
           artifacts: []
         })}

      _missing_or_wrong_lane ->
        {:error, :tre_governed_lower_envelope_required,
         RuntimeResult.new!(%{
           output: %{
             error: "tre_governed_lower_envelope_required",
             capability_id: capability.id
           },
           events: [
             %{
               type: "tre.fake.rejected",
               stream: :control,
               level: :warn,
               payload: %{reason: "tre_governed_lower_envelope_required"}
             }
           ],
           artifacts: []
         })}
    end
  end

  defp governed_lower_envelope(%{opts: opts}) when is_map(opts) do
    Map.get(opts, :governed_lower_envelope) || Map.get(opts, "governed_lower_envelope")
  end

  defp governed_lower_envelope(_context), do: nil

  defp governed_lower_receipt!(%GovernedLowerEnvelope{} = envelope, context) do
    envelope
    |> Map.from_struct()
    |> Map.take(@receipt_copy_fields)
    |> Map.merge(%{
      lower_receipt_ref:
        "lower-receipt://#{URI.encode_www_form(envelope.lower_request_ref)}/tre-fake/succeeded",
      status: :succeeded,
      artifact_refs: [],
      event_refs: [
        "lower-event://#{URI.encode_www_form(envelope.lower_request_ref)}/tre.fake.completed"
      ],
      extensions: receipt_extensions(envelope, context)
    })
    |> GovernedLowerReceipt.new!()
  end

  defp receipt_extensions(%GovernedLowerEnvelope{} = envelope, context) do
    Map.merge(envelope.extensions || %{}, %{
      "jido_integration" => %{
        "adapter" => "fake_tre",
        "run_id" => Map.get(context, :run_id),
        "attempt_id" => Map.get(context, :attempt_id)
      }
    })
  end
end
