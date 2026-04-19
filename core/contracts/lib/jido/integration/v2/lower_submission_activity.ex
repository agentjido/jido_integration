defmodule Jido.Integration.V2.LowerSubmissionActivity do
  @moduledoc """
  Activity-facing lower submission contract for Phase 4 durable workflows.

  Mezzanine workflow workers execute the activity wrapper. Jido Integration owns
  lower submission truth and dedupes repeated retries by tenant and submission
  dedupe key.
  """

  alias Jido.Integration.V2.EnterprisePrecutMetadataSupport

  @contract_name "JidoIntegration.LowerSubmissionActivity.v1"
  @idempotency_scope "tenant_ref + submission_dedupe_key"

  @fields [
    :contract_name,
    :tenant_ref,
    :principal_ref,
    :system_actor_ref,
    :resource_ref,
    :workflow_ref,
    :activity_call_ref,
    :lower_submission_ref,
    :submission_dedupe_key,
    :authority_packet_ref,
    :permission_decision_ref,
    :trace_id,
    :idempotency_key,
    :lower_scope_ref,
    :lease_ref,
    :lease_evidence_ref,
    :payload_ref,
    :payload_hash,
    :retry_policy,
    :timeout_policy,
    :heartbeat_policy,
    :release_manifest_ref
  ]

  @required [
    :tenant_ref,
    :resource_ref,
    :workflow_ref,
    :activity_call_ref,
    :lower_submission_ref,
    :submission_dedupe_key,
    :authority_packet_ref,
    :permission_decision_ref,
    :trace_id,
    :idempotency_key,
    :lower_scope_ref,
    :lease_ref,
    :lease_evidence_ref,
    :payload_hash,
    :retry_policy,
    :timeout_policy,
    :release_manifest_ref
  ]

  defstruct @fields

  @type t :: %__MODULE__{}

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec idempotency_scope() :: String.t()
  def idempotency_scope, do: @idempotency_scope

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) do
    with {:ok, activity} <-
           EnterprisePrecutMetadataSupport.build(
             __MODULE__,
             @contract_name,
             @fields,
             @required,
             attrs
           ),
         :ok <- require_actor(activity) do
      {:ok, activity}
    end
  end

  @spec dedupe_key(t()) :: {String.t(), String.t()}
  def dedupe_key(%__MODULE__{} = activity),
    do: {activity.tenant_ref, activity.submission_dedupe_key}

  @spec same_retry_scope?(t(), t()) :: boolean()
  def same_retry_scope?(%__MODULE__{} = left, %__MODULE__{} = right),
    do: dedupe_key(left) == dedupe_key(right)

  @spec to_ledger_lookup(t()) :: %{tenant_id: String.t(), submission_dedupe_key: String.t()}
  def to_ledger_lookup(%__MODULE__{} = activity),
    do: %{tenant_id: activity.tenant_ref, submission_dedupe_key: activity.submission_dedupe_key}

  defp require_actor(%__MODULE__{
         principal_ref: principal_ref,
         system_actor_ref: system_actor_ref
       })
       when is_binary(principal_ref) or is_binary(system_actor_ref),
       do: :ok

  defp require_actor(_activity),
    do: {:error, {:missing_one_of, [:principal_ref, :system_actor_ref]}}
end
