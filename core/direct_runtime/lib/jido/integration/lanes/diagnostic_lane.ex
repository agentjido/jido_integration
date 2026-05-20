defmodule Jido.Integration.Lanes.DiagnosticLane do
  @moduledoc """
  Direct-runtime connector for the provider-neutral Execution Plane diagnostic lane.
  """

  alias ExecutionPlane.ExecutionRequest
  alias ExecutionPlane.Lanes.DiagnosticLane, as: ExecutionDiagnosticLane
  alias Jido.Integration.Lanes.LowerEffectReceipt
  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.GovernedLowerEnvelope
  alias Jido.Integration.V2.GovernedLowerReceipt
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.RuntimeResult

  @connector "diagnostic_lane"
  @connector_ref "connector://diagnostic_lane"
  @manifest_ref "manifest://jido/diagnostic_lane/v1"
  @operation_ids [
    "diagnostic.echo",
    "diagnostic.system_info",
    "diagnostic.http_probe",
    "diagnostic.workspace_stat"
  ]
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

  @spec connector_ref() :: String.t()
  def connector_ref, do: @connector_ref

  @spec manifest_ref() :: String.t()
  def manifest_ref, do: @manifest_ref

  @spec operation_ids() :: [String.t()]
  def operation_ids, do: @operation_ids

  @spec manifest_hash() :: String.t()
  def manifest_hash, do: manifest() |> Manifest.canonical_hash()

  @spec manifest() :: Manifest.t()
  def manifest do
    Manifest.new!(%{
      connector: @connector,
      auth:
        AuthSpec.new!(%{
          binding_kind: :none,
          auth_type: :none,
          install: %{required: false},
          reauth: %{supported: false},
          requested_scopes: [],
          durable_secret_fields: [],
          lease_fields: [],
          secret_names: []
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: "Diagnostic Lane",
          description: "Provider-neutral local diagnostic lower lane",
          category: "platform_diagnostics",
          tags: ["diagnostic", "local", "governed_effect"],
          docs_refs: [],
          maturity: :alpha,
          publication: :internal
        }),
      operations: Enum.map(@operation_ids, &operation_spec/1),
      triggers: [],
      runtime_families: [:direct],
      metadata: %{
        connector_kind: :platform_diagnostic,
        credential_materialization: :none,
        provider_dependency: :none
      }
    })
  end

  @spec run(map(), map()) :: {:ok, RuntimeResult.t()} | {:error, atom(), RuntimeResult.t()}
  def run(input, context) when is_map(input) and is_map(context) do
    with {:ok, %Capability{} = capability} <- fetch_capability(context),
         {:ok, %GovernedLowerEnvelope{} = envelope} <- fetch_envelope(input, context),
         :ok <- validate_effect_envelope(envelope, capability),
         {:ok, lower_result} <- execute_lower(input, envelope, capability) do
      receipt = lower_effect_receipt!(envelope, lower_result)
      governed_receipt = governed_lower_receipt!(envelope, lower_result, receipt)
      evidence = aitrace_evidence(envelope, receipt, lower_result)

      {:ok,
       RuntimeResult.new!(%{
         output: %{
           "lower_effect_receipt" => LowerEffectReceipt.to_map(receipt),
           "governed_lower_receipt" => GovernedLowerReceipt.to_map(governed_receipt),
           "aitrace_evidence" => evidence
         },
         events: [
           %{
             type: "diagnostic_lane.executed",
             payload: %{
               effect_ref: envelope.effect_ref,
               receipt_ref: receipt.receipt_ref,
               status: Atom.to_string(receipt.status)
             },
             trace: %{"trace_ref" => envelope.trace_id}
           }
         ]
       })}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason, error_result(reason)}
    end
  end

  defp operation_spec(operation_id) do
    OperationSpec.new!(%{
      operation_id: operation_id,
      name: operation_name(operation_id),
      display_name: operation_display_name(operation_id),
      description: "Runs #{operation_id} through the local diagnostic lower lane",
      runtime_class: :direct,
      transport_mode: :diagnostic,
      handler: __MODULE__,
      input_schema:
        Zoi.object(%{
          message: Zoi.string() |> Zoi.optional(),
          url: Zoi.string() |> Zoi.optional(),
          path: Zoi.string() |> Zoi.optional()
        }),
      output_schema:
        Zoi.object(%{
          lower_effect_receipt: Contracts.any_map_schema(),
          governed_lower_receipt: Contracts.any_map_schema(),
          aitrace_evidence: Contracts.any_map_schema()
        }),
      permissions: %{required_scopes: []},
      runtime: %{
        driver: "diagnostic_lane",
        options: %{lane_id: "diagnostic"}
      },
      policy: %{
        sandbox: %{
          level: :strict,
          egress: :localhost_only,
          approvals: :auto,
          workspace_mutability: :read_only
        }
      },
      upstream: %{protocol: :diagnostic},
      consumer_surface: %{
        mode: :connector_local,
        reason: "diagnostic lane is a platform proof connector"
      },
      schema_policy: %{input: :defined, output: :defined},
      jido: %{action: %{name: operation_name(operation_id)}},
      metadata: %{
        lower_runtime_kinds: [:direct_connector],
        side_effect_class: :read,
        idempotency_class: :idempotent,
        operation_class: :resource_effect,
        binding_kind: :resource_effect,
        evidence_tier: :standard,
        deterministic_fixture_support: false
      }
    })
  end

  defp fetch_capability(%{capability: %Capability{} = capability}), do: {:ok, capability}
  defp fetch_capability(%{"capability" => %Capability{} = capability}), do: {:ok, capability}
  defp fetch_capability(_context), do: {:error, :capability_required}

  defp fetch_envelope(input, context) do
    envelope =
      Contracts.get(context, :governed_lower_envelope) ||
        Contracts.get(input, :governed_lower_envelope)

    case envelope do
      %GovernedLowerEnvelope{} = envelope -> {:ok, envelope}
      attrs when is_map(attrs) -> GovernedLowerEnvelope.new(attrs)
      _other -> {:error, :governed_lower_envelope_required}
    end
  end

  defp validate_effect_envelope(%GovernedLowerEnvelope{effect_ref: nil}, _capability),
    do: {:error, :effect_ref_required}

  defp validate_effect_envelope(%GovernedLowerEnvelope{effect_ref: ""}, _capability),
    do: {:error, :effect_ref_required}

  defp validate_effect_envelope(%GovernedLowerEnvelope{} = envelope, %Capability{} = capability) do
    if envelope.capability_id == capability.id do
      :ok
    else
      {:error, :capability_mismatch}
    end
  end

  defp execute_lower(input, %GovernedLowerEnvelope{} = envelope, %Capability{} = capability) do
    request =
      ExecutionRequest.new!(
        execution_ref: envelope.lower_request_ref,
        lane_id: "diagnostic",
        operation: capability.id,
        payload: diagnostic_payload(input),
        provenance: ExecutionPlane.Provenance.direct_lower_lane_owner("jido_integration")
      )

    case ExecutionDiagnosticLane.execute(request, []) do
      {:ok, result} -> {:ok, result}
      {:error, result} -> {:ok, result}
    end
  end

  defp diagnostic_payload(input) do
    input
    |> Map.drop([:governed_lower_envelope, "governed_lower_envelope"])
    |> Map.take(["message", :message, "url", :url, "path", :path])
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp lower_effect_receipt!(%GovernedLowerEnvelope{} = envelope, lower_result) do
    diagnostic_result = lower_result.output["diagnostic_result"]
    receipt_ref = receipt_ref(envelope)

    LowerEffectReceipt.new!(%{
      receipt_ref: receipt_ref,
      effect_ref: envelope.effect_ref,
      status: receipt_status(lower_result.status),
      lower_receipt_ref: lower_receipt_ref(envelope),
      lower_facts: %{
        "diagnostic_result" => diagnostic_result,
        "execution_ref" => lower_result.execution_ref,
        "authority_ref" => envelope.authority_ref,
        "expected_version" => envelope.expected_version,
        "compensation_posture" => atomish_to_string(envelope.compensation_posture)
      },
      projection_updates: [
        %{
          "kind" => "diagnostic_effect_completed",
          "effect_ref" => envelope.effect_ref,
          "status" => lower_result.status
        }
      ],
      evidence_refs: [evidence_ref(envelope, receipt_ref)],
      trace_ref: envelope.trace_id,
      completed_at: DateTime.utc_now()
    })
  end

  defp governed_lower_receipt!(%GovernedLowerEnvelope{} = envelope, lower_result, receipt) do
    envelope
    |> Map.from_struct()
    |> Map.take(@receipt_copy_fields)
    |> Map.merge(%{
      lower_receipt_ref: lower_receipt_ref(envelope),
      status: governed_status(lower_result.status),
      artifact_refs: [],
      event_refs: receipt.evidence_refs,
      observed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      extensions: %{
        "lower_effect_receipt_ref" => receipt.receipt_ref,
        "diagnostic_result" => lower_result.output["diagnostic_result"]
      }
    })
    |> GovernedLowerReceipt.new!()
  end

  defp aitrace_evidence(%GovernedLowerEnvelope{} = envelope, receipt, lower_result) do
    %{
      "evidence_ref" => evidence_ref(envelope, receipt.receipt_ref),
      "effect_ref" => envelope.effect_ref,
      "authority_ref" => envelope.authority_ref,
      "receipt_ref" => receipt.receipt_ref,
      "trace_ref" => envelope.trace_id,
      "redaction_profile_ref" => envelope.redaction_profile_ref,
      "lower_status" => lower_result.status,
      "payload_ref" => "claim-check://diagnostic/#{encoded_effect_ref(envelope)}"
    }
  end

  defp error_result(reason) do
    RuntimeResult.new!(%{
      output: %{"reason" => Atom.to_string(reason)},
      events: [%{type: "diagnostic_lane.rejected", payload: %{reason: Atom.to_string(reason)}}]
    })
  end

  defp operation_name(operation_id) do
    operation_id
    |> String.replace(".", "_")
    |> String.replace("-", "_")
  end

  defp operation_display_name("diagnostic.echo"), do: "Diagnostic echo"
  defp operation_display_name("diagnostic.system_info"), do: "Diagnostic system info"
  defp operation_display_name("diagnostic.http_probe"), do: "Diagnostic HTTP probe"
  defp operation_display_name("diagnostic.workspace_stat"), do: "Diagnostic workspace stat"

  defp receipt_status("succeeded"), do: :success
  defp receipt_status("timeout"), do: :timeout
  defp receipt_status(_status), do: :failure

  defp governed_status("succeeded"), do: :succeeded
  defp governed_status("timeout"), do: :timed_out
  defp governed_status(_status), do: :failed

  defp receipt_ref(%GovernedLowerEnvelope{} = envelope) do
    "receipt://jido/diagnostic/#{encoded_effect_ref(envelope)}"
  end

  defp lower_receipt_ref(%GovernedLowerEnvelope{} = envelope) do
    "lower-receipt://jido/diagnostic/#{encoded_effect_ref(envelope)}"
  end

  defp evidence_ref(%GovernedLowerEnvelope{} = envelope, receipt_ref) do
    "aitrace://#{encoded_effect_ref(envelope)}/#{URI.encode_www_form(receipt_ref)}"
  end

  defp encoded_effect_ref(%GovernedLowerEnvelope{} = envelope) do
    URI.encode_www_form(envelope.effect_ref || envelope.lower_request_ref)
  end

  defp atomish_to_string(nil), do: nil
  defp atomish_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atomish_to_string(value), do: to_string(value)
end
