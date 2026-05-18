defmodule Jido.Integration.V2.RuntimeRouter.ExecutionPlaneTreAdapter do
  @moduledoc """
  Jido adapter for the ExecutionPlane-owned local TRE/Rhai lane.

  This module is intentionally an explicit `:tre_adapter`. The ControlPlane
  keeps `:tre_rhai` unavailable by default, and callers must opt in by passing
  this adapter plus runner/materializer options.
  """

  alias ExecutionPlane.Process.TreRhai
  alias GroundPlane.Boundary.Codec, as: BoundaryCodec

  alias Jido.Integration.V2.{
    CanonicalJson,
    Capability,
    GovernedLowerEnvelope,
    GovernedLowerReceipt,
    RuntimeResult
  }

  @tre_contract_version "nshkr.execution_plane.tre.v1"
  @default_limits %{
    "max_operations" => 1_000,
    "wall_clock_ms" => 30_000,
    "max_output_bytes" => 65_536,
    "max_artifact_bytes" => 1_048_576,
    "max_network_calls" => 0,
    "max_process_spawns" => 0
  }

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
        execute_with_envelope(capability, envelope, input, context)

      _missing_or_wrong_lane ->
        {:error, :tre_governed_lower_envelope_required,
         runtime_result(
           capability,
           nil,
           nil,
           :failed,
           "tre_governed_lower_envelope_required",
           %{}
         )}
    end
  end

  defp execute_with_envelope(capability, envelope, input, context) do
    tre_envelope = tre_envelope(envelope, input, context)

    opts = %{
      runner_path: context_opt(context, :tre_runner_path),
      materializer: context_opt(context, :tre_materializer),
      cleanup?: context_opt(context, :tre_cleanup?, true),
      verify_script_hash?: context_opt(context, :tre_verify_script_hash?, true)
    }

    runner_opts = opts |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Keyword.new()

    case TreRhai.execute(tre_envelope, runner_opts) do
      {:ok, execution_plane_receipt} ->
        {:ok,
         runtime_result(capability, envelope, context, :succeeded, nil, execution_plane_receipt)}

      {:error, %{"status" => "denied"} = execution_plane_receipt} ->
        {:error, :tre_denied,
         runtime_result(
           capability,
           envelope,
           context,
           :denied,
           "tre_denied",
           execution_plane_receipt
         )}

      {:error, execution_plane_receipt} ->
        {:error, :tre_failed,
         runtime_result(
           capability,
           envelope,
           context,
           :failed,
           "tre_failed",
           execution_plane_receipt
         )}
    end
  end

  defp tre_envelope(%GovernedLowerEnvelope{} = envelope, input, context) do
    %{
      "version" => @tre_contract_version,
      "authority_ref" => envelope.authority_ref,
      "policy_bundle_ref" => envelope.policy_bundle_ref,
      "policy_bundle_hash" => envelope.policy_bundle_hash,
      "cedar_schema_ref" => envelope.cedar_schema_ref,
      "cedar_schema_hash" => envelope.cedar_schema_hash,
      "script_ref" => envelope.script_ref,
      "script_hash" => envelope.script_hash,
      "trace_id" => envelope.trace_id,
      "declared_actions" => envelope.declared_actions,
      "allowed_actions" => context_opt(context, :tre_allowed_actions, envelope.declared_actions),
      "resource_scope_refs" => envelope.resource_scope_refs,
      "workspace_ref" => envelope.workspace_ref,
      "target_ref" => envelope.target_ref,
      "runtime_profile_ref" => envelope.runtime_profile_ref,
      "sandbox_profile_ref" => envelope.sandbox_profile_ref,
      "input_ref" => envelope.input_ref,
      "input_hash" => envelope.input_hash,
      "input_shape_hash" => boundary_digest(input),
      "limits" => context_opt(context, :tre_limits, @default_limits)
    }
  end

  defp runtime_result(capability, envelope, context, status, reason, execution_plane_receipt) do
    governed_receipt =
      case envelope do
        %GovernedLowerEnvelope{} ->
          envelope
          |> governed_lower_receipt!(context, status, execution_plane_receipt)
          |> GovernedLowerReceipt.to_map()

        _other ->
          nil
      end

    RuntimeResult.new!(%{
      output: %{
        adapter: :execution_plane_tre,
        capability_id: capability.id,
        lower_runtime_kind: envelope && envelope.lower_runtime_kind,
        lower_request_ref: envelope && envelope.lower_request_ref,
        execution_plane_receipt: execution_plane_receipt,
        governed_lower_receipt: governed_receipt,
        error: reason
      },
      runtime_ref_id: runtime_ref(envelope, execution_plane_receipt),
      events: runtime_events(envelope, status, reason, execution_plane_receipt),
      artifacts: []
    })
  end

  defp governed_lower_receipt!(
         %GovernedLowerEnvelope{} = envelope,
         context,
         status,
         execution_receipt
       ) do
    envelope
    |> Map.from_struct()
    |> Map.take(@receipt_copy_fields)
    |> Map.merge(%{
      lower_receipt_ref:
        "lower-receipt://#{URI.encode_www_form(envelope.lower_request_ref)}/execution-plane-tre/#{status}",
      status: status,
      artifact_refs: string_list(execution_receipt["artifact_refs"]),
      event_refs: string_list(execution_receipt["event_refs"]),
      extensions: receipt_extensions(envelope, context, execution_receipt)
    })
    |> GovernedLowerReceipt.new!()
  end

  defp receipt_extensions(%GovernedLowerEnvelope{} = envelope, context, execution_receipt) do
    Map.merge(envelope.extensions || %{}, %{
      "jido_integration" => %{
        "adapter" => "execution_plane_tre",
        "run_id" => Map.get(context, :run_id),
        "attempt_id" => Map.get(context, :attempt_id)
      },
      "execution_plane" => %{
        "receipt_ref" => execution_receipt["receipt_ref"],
        "contract_version" => execution_receipt["contract_version"],
        "status" => execution_receipt["status"],
        "runner_envelope_hash" => execution_receipt["runner_envelope_hash"]
      }
    })
  end

  defp runtime_events(envelope, status, reason, execution_receipt) do
    [
      %{
        type: "tre.execution_plane.completed",
        stream: :control,
        level: event_level(status),
        payload: %{
          lower_request_ref: envelope && envelope.lower_request_ref,
          lower_runtime_kind: "tre_rhai",
          status: Atom.to_string(status),
          reason: reason,
          execution_plane_receipt_ref: execution_receipt["receipt_ref"]
        }
      }
    ]
  end

  defp event_level(:succeeded), do: :info
  defp event_level(:denied), do: :warn
  defp event_level(_status), do: :error

  defp runtime_ref(nil, _receipt), do: nil

  defp runtime_ref(%GovernedLowerEnvelope{} = envelope, execution_receipt) do
    receipt_ref = execution_receipt["receipt_ref"] || envelope.lower_request_ref
    "tre-execution-plane://#{URI.encode_www_form(receipt_ref)}"
  end

  defp governed_lower_envelope(%{opts: opts}) when is_map(opts) do
    Map.get(opts, :governed_lower_envelope) || Map.get(opts, "governed_lower_envelope")
  end

  defp governed_lower_envelope(_context), do: nil

  defp context_opt(context, key, default \\ nil)

  defp context_opt(%{opts: opts}, key, default) when is_map(opts) do
    Map.get(opts, key, Map.get(opts, Atom.to_string(key), default))
  end

  defp context_opt(_context, _key, default), do: default

  defp string_list(values) when is_list(values), do: Enum.map(values, &to_string/1)
  defp string_list(nil), do: []
  defp string_list(value), do: [to_string(value)]

  defp boundary_digest(value) do
    value
    |> CanonicalJson.normalize!()
    |> BoundaryCodec.digest()
  end
end
