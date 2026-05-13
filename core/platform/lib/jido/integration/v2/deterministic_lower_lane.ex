defmodule Jido.Integration.V2.DeterministicLowerLane do
  @moduledoc """
  Deterministic governed lower lane for no-live-credential product proofs.

  The lane consumes the same governed lower envelope that live connector and
  session dispatchers receive. It returns a terminal governed receipt plus
  projection facts for Codex app-server events, Linear source publication, and
  GitHub PR evidence without touching provider SDKs.
  """

  alias Jido.Integration.V2.GovernedLowerEnvelope
  alias Jido.Integration.V2.GovernedLowerReceipt

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

  @spec invoke(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def invoke(capability_id, input, opts)
      when is_binary(capability_id) and is_map(input) and is_list(opts) do
    with {:ok, envelope} <- governed_lower_envelope(input, opts) do
      receipt = governed_lower_receipt!(envelope)
      projection_facts = projection_facts(capability_id, envelope, receipt, input)

      {:ok,
       %{
         capability_id: capability_id,
         run_id: deterministic_run_id(envelope),
         attempt_id: deterministic_attempt_id(envelope),
         run: %{run_id: deterministic_run_id(envelope)},
         attempt: %{attempt_id: deterministic_attempt_id(envelope)},
         artifact_refs: projection_facts.artifact_ref_strings,
         event_refs: projection_facts.event_refs,
         output: %{
           deterministic_lower: Map.drop(projection_facts, [:artifact_ref_strings]),
           governed_lower_receipt: GovernedLowerReceipt.to_map(receipt)
         }
       }}
    end
  end

  defp governed_lower_envelope(_input, opts) do
    case Keyword.get(opts, :governed_lower_envelope) do
      %GovernedLowerEnvelope{} = envelope ->
        {:ok, envelope}

      %{} = attrs ->
        GovernedLowerEnvelope.new(attrs)

      nil ->
        {:error, :governed_lower_envelope_required}
    end
  end

  defp governed_lower_receipt!(%GovernedLowerEnvelope{} = envelope) do
    envelope
    |> Map.from_struct()
    |> Map.take(@receipt_copy_fields)
    |> Map.merge(%{
      lower_receipt_ref: deterministic_lower_receipt_ref(envelope),
      status: :succeeded,
      artifact_refs: artifact_ref_strings(envelope),
      event_refs: event_refs(envelope),
      observed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      extensions: receipt_extensions(envelope)
    })
    |> GovernedLowerReceipt.new!()
  end

  defp projection_facts(capability_id, envelope, receipt, input) do
    lower_receipt_ref = receipt.lower_receipt_ref
    lower_request_ref = envelope.lower_request_ref
    encoded = encoded_request_ref(envelope)

    %{
      lower_receipt_ref: lower_receipt_ref,
      lower_request_ref: lower_request_ref,
      lower_runtime_kind: atomish_to_string(envelope.lower_runtime_kind),
      capability_id: capability_id,
      status: "succeeded",
      provider_object_refs: [
        "codex-session://#{encoded}",
        "linear-comment://#{encoded}",
        "github-pr://#{encoded}"
      ],
      artifact_refs: artifact_refs(envelope),
      artifact_ref_strings: artifact_ref_strings(envelope),
      event_refs: event_refs(envelope),
      runtime_events: runtime_events(envelope),
      token_totals: %{"input" => 128, "output" => 64, "total" => 192},
      token_dedupe: %{
        "accepted_count" => 1,
        "duplicate_count" => 0,
        "token_hash_refs" => ["token-hash://#{encoded}/turn-1"]
      },
      rate_limit: %{
        "remaining" => 100,
        "window" => "deterministic",
        "source_event_ref" => "lower-event://#{encoded}/codex.rate_limit.observed"
      },
      retry: [],
      retry_receipts: [],
      aitrace: %{
        "evidence_receipt_ref" => "aitrace://#{encoded}/receipt",
        "trace_artifact_ref" => "artifact://#{encoded}/codex-event-log",
        "export_bounds" => %{
          "schema_version" => "aitrace.redacted.v1",
          "redaction_policy_ref" => envelope.redaction_profile_ref,
          "overflow_safe_action" => "claim_check"
        }
      },
      prompt_provenance: %{
        "semantic_ref" => "prompt://#{encoded}/semantic",
        "prompt_hash" =>
          "sha256:" <> sha256(Map.get(input, :prompt) || Map.get(input, "prompt") || ""),
        "context_hash" => "sha256:" <> sha256(inspect(Map.get(input, :provider_metadata, %{}))),
        "input_claim_check_ref" => envelope.input_ref,
        "output_claim_check_ref" => "claim-check://#{encoded}/codex-output",
        "provenance_refs" => ["prompt-provenance://#{encoded}"],
        "normalizer_version" => "deterministic-lower-lane.v1",
        "redaction_policy_ref" => envelope.redaction_profile_ref
      },
      memory_context: %{
        "memory_profile_ref" => "memory://runtime/none",
        "context_pack_ref" => "memory-context://#{encoded}/empty",
        "context_hash" => "sha256:" <> sha256("empty"),
        "fragment_refs" => [],
        "redaction_policy_ref" => envelope.redaction_profile_ref
      },
      provider_account: %{
        "provider_account_ref" => "provider-account://deterministic/codex/redacted",
        "redaction" => "ref_only"
      },
      credential: %{
        "credential_ref" => "credential://deterministic/no-live-secret",
        "redaction" => "not_materialized"
      },
      runtime_profile: %{
        "runtime_profile_ref" => envelope.runtime_profile_ref,
        "runtime_profile_kind" => atomish_to_string(envelope.runtime_profile_kind)
      },
      governed_lower_envelope: GovernedLowerEnvelope.to_map(envelope),
      authority_decision: %{
        "authority_ref" => envelope.authority_ref,
        "authority_decision_hash" => envelope.authority_decision_hash
      },
      connector_manifests: connector_manifests(envelope),
      capability_negotiations: capability_negotiations(envelope),
      incident_bundles: [],
      acceptance: %{
        "scenario_refs" => [
          "scenario://codex-session-turn/deterministic",
          "scenario://linear-comments-update/deterministic",
          "scenario://github-pr-evidence/deterministic"
        ],
        "claim_refs" => [
          "claim://deterministic-lower-lane/no-live-credentials",
          "claim://deterministic-lower-lane/governed-envelope"
        ]
      },
      github_pr_evidence: github_pr_evidence(envelope),
      source_publication: source_publication(envelope, lower_receipt_ref),
      workpad_refs: ["source-workpad://#{encoded}/operator-review"]
    }
  end

  defp connector_manifests(%GovernedLowerEnvelope{} = envelope) do
    [
      %{
        "connector_manifest_ref" => envelope.connector_manifest_ref,
        "connector_manifest_hash" => envelope.connector_manifest_hash,
        "connector_manifest_state" => atomish_to_string(envelope.connector_manifest_state)
      },
      %{
        "connector_manifest_ref" => "manifest://jido/connectors/linear@deterministic",
        "connector_manifest_hash" => "sha256:" <> sha256("linear.comments.update"),
        "connector_manifest_state" => "active"
      },
      %{
        "connector_manifest_ref" => "manifest://jido/connectors/github@deterministic",
        "connector_manifest_hash" => "sha256:" <> sha256("github.pr.evidence"),
        "connector_manifest_state" => "active"
      }
    ]
  end

  defp capability_negotiations(%GovernedLowerEnvelope{} = envelope) do
    encoded = encoded_request_ref(envelope)

    [
      %{"capability_negotiation_ref" => envelope.capability_negotiation_ref},
      %{"capability_negotiation_ref" => "cap-neg://#{encoded}/linear.comments.update"},
      %{"capability_negotiation_ref" => "cap-neg://#{encoded}/github.pr.evidence"}
    ]
  end

  defp github_pr_evidence(%GovernedLowerEnvelope{} = envelope) do
    encoded = encoded_request_ref(envelope)

    %{
      "provider" => "github",
      "evidence_ref" => "evidence://github-pr/#{encoded}",
      "content_ref" => "github-pr://#{encoded}",
      "feedback" => []
    }
  end

  defp source_publication(%GovernedLowerEnvelope{} = envelope, lower_receipt_ref) do
    encoded = encoded_request_ref(envelope)

    %{
      "source_publication_receipt_ref" =>
        "source-publication://#{encoded}/linear-comments-update",
      "source_publish_ref" => "linear_workpad_review",
      "status" => "published",
      "capability_id" => "linear.comments.update",
      "lower_runtime_kind" => atomish_to_string(envelope.lower_runtime_kind),
      "lower_request_ref" => envelope.lower_request_ref,
      "lower_receipt_ref" => lower_receipt_ref,
      "authority_ref" => envelope.authority_ref,
      "authority_decision_hash" => envelope.authority_decision_hash,
      "connector_manifest_ref" => "manifest://jido/connectors/linear@deterministic",
      "capability_negotiation_ref" => "cap-neg://#{encoded}/linear.comments.update",
      "provider_response_ref" => "linear-comment://#{encoded}",
      "redaction_manifest_ref" => "redaction://#{encoded}/linear-comment",
      "workpad_refs" => ["source-workpad://#{encoded}/operator-review"],
      "comment_ref" => "linear-comment://#{encoded}",
      "trace_id" => envelope.trace_id
    }
  end

  defp artifact_refs(%GovernedLowerEnvelope{} = envelope) do
    encoded = encoded_request_ref(envelope)

    [
      %{
        "kind" => "github_pr",
        "content_ref" => "github-pr://#{encoded}",
        "collector_ref" => "deterministic_lower_lane"
      },
      %{
        "kind" => "codex_session",
        "content_ref" => "codex-session://#{encoded}",
        "collector_ref" => "deterministic_lower_lane"
      },
      %{
        "kind" => "source_workpad",
        "content_ref" => "source-workpad://#{encoded}/operator-review",
        "collector_ref" => "deterministic_lower_lane"
      }
    ]
  end

  defp artifact_ref_strings(%GovernedLowerEnvelope{} = envelope) do
    envelope
    |> artifact_refs()
    |> Enum.map(&Map.fetch!(&1, "content_ref"))
  end

  defp runtime_events(%GovernedLowerEnvelope{} = envelope) do
    encoded = encoded_request_ref(envelope)

    [
      "codex.session.started",
      "codex.approval.required",
      "codex.approval.auto_approved",
      "codex.input.required",
      "codex.tool.unsupported",
      "codex.tool_input.auto_answered",
      "codex.dynamic_tool.completed",
      "codex.dynamic_tool.failed",
      "codex.dynamic_tool.unsupported",
      "codex.json.malformed",
      "codex.diagnostic.non_json",
      "codex.token.usage",
      "codex.rate_limit.observed",
      "codex.timeout",
      "codex.cancelled",
      "codex.app_server.shutdown",
      "codex.session.completed"
    ]
    |> Enum.with_index(1)
    |> Enum.map(fn {event_kind, seq} ->
      %{
        "event_ref" => "lower-event://#{encoded}/#{event_kind}",
        "event_seq" => seq,
        "event_kind" => event_kind,
        "observed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "subject_ref" => envelope.subject_ref,
        "run_ref" => envelope.run_ref,
        "workflow_ref" => envelope.workflow_ref,
        "payload_ref" => "payload://redacted/#{encoded}/#{event_kind}"
      }
    end)
  end

  defp event_refs(%GovernedLowerEnvelope{} = envelope) do
    envelope
    |> runtime_events()
    |> Enum.map(&Map.fetch!(&1, "event_ref"))
  end

  defp receipt_extensions(%GovernedLowerEnvelope{} = envelope) do
    Map.merge(envelope.extensions || %{}, %{
      "jido_integration" => %{
        "lane" => "deterministic_lower",
        "run_id" => deterministic_run_id(envelope),
        "attempt_id" => deterministic_attempt_id(envelope),
        "linear_publication" => "linear.comments.update",
        "github_evidence" => "github.pr"
      }
    })
  end

  defp deterministic_lower_receipt_ref(%GovernedLowerEnvelope{} = envelope) do
    "lower-receipt://#{encoded_request_ref(envelope)}/deterministic/succeeded"
  end

  defp deterministic_run_id(%GovernedLowerEnvelope{} = envelope) do
    "jido-run://#{encoded_request_ref(envelope)}/deterministic"
  end

  defp deterministic_attempt_id(%GovernedLowerEnvelope{} = envelope) do
    "#{deterministic_run_id(envelope)}:1"
  end

  defp encoded_request_ref(%GovernedLowerEnvelope{} = envelope) do
    URI.encode_www_form(envelope.lower_request_ref)
  end

  defp sha256(value), do: :crypto.hash(:sha256, to_string(value)) |> Base.encode16(case: :lower)

  defp atomish_to_string(nil), do: nil
  defp atomish_to_string(value) when is_atom(value), do: Atom.to_string(value)
  defp atomish_to_string(value) when is_binary(value), do: value
end
