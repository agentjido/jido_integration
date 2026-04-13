defmodule Jido.Integration.V2.BrainInvocation do
  @moduledoc """
  Durable Brain-to-Spine invocation handoff packet.
  """

  alias Jido.Integration.V2.AuthorityAuditEnvelope
  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ExecutionGovernanceProjection
  alias Jido.Integration.V2.SubmissionIdentity

  @contract_version "v1"

  @type t :: %__MODULE__{
          contract_version: String.t(),
          submission_identity: SubmissionIdentity.t(),
          submission_key: Contracts.checksum(),
          request_id: String.t(),
          session_id: String.t(),
          tenant_id: String.t(),
          trace_id: String.t(),
          actor_id: String.t(),
          target_id: String.t(),
          target_kind: String.t(),
          runtime_class: Contracts.runtime_class(),
          allowed_operations: [String.t()],
          authority_payload: AuthorityAuditEnvelope.t(),
          authority_payload_hash: Contracts.checksum(),
          execution_governance_payload: ExecutionGovernanceProjection.t(),
          execution_governance_payload_hash: Contracts.checksum(),
          gateway_request: map(),
          runtime_request: map(),
          boundary_request: map(),
          execution_intent_family: String.t(),
          execution_intent: map(),
          extensions: map()
        }

  @enforce_keys [
    :contract_version,
    :submission_identity,
    :submission_key,
    :request_id,
    :session_id,
    :tenant_id,
    :trace_id,
    :actor_id,
    :target_id,
    :target_kind,
    :runtime_class,
    :allowed_operations,
    :authority_payload,
    :authority_payload_hash,
    :execution_governance_payload,
    :execution_governance_payload_hash,
    :gateway_request,
    :runtime_request,
    :boundary_request,
    :execution_intent_family,
    :execution_intent,
    :extensions
  ]
  defstruct @enforce_keys

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = invocation), do: normalize(invocation)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = invocation) do
    case normalize(invocation) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = invocation) do
    %{
      contract_version: invocation.contract_version,
      submission_identity: SubmissionIdentity.dump(invocation.submission_identity),
      submission_key: invocation.submission_key,
      request_id: invocation.request_id,
      session_id: invocation.session_id,
      tenant_id: invocation.tenant_id,
      trace_id: invocation.trace_id,
      actor_id: invocation.actor_id,
      target_id: invocation.target_id,
      target_kind: invocation.target_kind,
      runtime_class: invocation.runtime_class,
      allowed_operations: invocation.allowed_operations,
      authority_payload: AuthorityAuditEnvelope.dump(invocation.authority_payload),
      authority_payload_hash: invocation.authority_payload_hash,
      execution_governance_payload:
        ExecutionGovernanceProjection.dump(invocation.execution_governance_payload),
      execution_governance_payload_hash: invocation.execution_governance_payload_hash,
      gateway_request: invocation.gateway_request,
      runtime_request: invocation.runtime_request,
      boundary_request: invocation.boundary_request,
      execution_intent_family: invocation.execution_intent_family,
      execution_intent: invocation.execution_intent,
      extensions: invocation.extensions
    }
  end

  defp build!(attrs) do
    attrs = Map.new(attrs)

    submission_identity =
      attrs
      |> fetch!(:submission_identity, "brain_invocation.submission_identity")
      |> validate_submission_identity!()

    authority_payload =
      attrs
      |> fetch!(:authority_payload, "brain_invocation.authority_payload")
      |> validate_authority_payload!()

    governance_payload =
      attrs
      |> fetch!(:execution_governance_payload, "brain_invocation.execution_governance_payload")
      |> validate_governance_payload!()

    computed_submission_key = SubmissionIdentity.submission_key(submission_identity)
    computed_authority_hash = AuthorityAuditEnvelope.payload_hash(authority_payload)
    computed_governance_hash = ExecutionGovernanceProjection.payload_hash(governance_payload)

    %__MODULE__{
      contract_version:
        validate_contract_version!(Map.get(attrs, :contract_version, @contract_version)),
      submission_identity: submission_identity,
      submission_key:
        validate_hash!(
          Map.get(attrs, :submission_key, computed_submission_key),
          computed_submission_key,
          "brain_invocation.submission_key"
        ),
      request_id:
        attrs
        |> fetch!(:request_id, "brain_invocation.request_id")
        |> validate_string!("brain_invocation.request_id"),
      session_id:
        attrs
        |> fetch!(:session_id, "brain_invocation.session_id")
        |> validate_string!("brain_invocation.session_id"),
      tenant_id:
        attrs
        |> fetch!(:tenant_id, "brain_invocation.tenant_id")
        |> validate_string!("brain_invocation.tenant_id"),
      trace_id:
        attrs
        |> fetch!(:trace_id, "brain_invocation.trace_id")
        |> validate_string!("brain_invocation.trace_id"),
      actor_id:
        attrs
        |> fetch!(:actor_id, "brain_invocation.actor_id")
        |> validate_string!("brain_invocation.actor_id"),
      target_id:
        attrs
        |> fetch!(:target_id, "brain_invocation.target_id")
        |> validate_string!("brain_invocation.target_id"),
      target_kind:
        attrs
        |> fetch!(:target_kind, "brain_invocation.target_kind")
        |> validate_string!("brain_invocation.target_kind"),
      runtime_class:
        attrs
        |> fetch!(:runtime_class, "brain_invocation.runtime_class")
        |> Contracts.validate_runtime_class!(),
      allowed_operations:
        attrs
        |> fetch!(:allowed_operations, "brain_invocation.allowed_operations")
        |> Contracts.normalize_string_list!("brain_invocation.allowed_operations"),
      authority_payload: authority_payload,
      authority_payload_hash:
        validate_hash!(
          Map.get(attrs, :authority_payload_hash, computed_authority_hash),
          computed_authority_hash,
          "brain_invocation.authority_payload_hash"
        ),
      execution_governance_payload: governance_payload,
      execution_governance_payload_hash:
        validate_hash!(
          Map.get(attrs, :execution_governance_payload_hash, computed_governance_hash),
          computed_governance_hash,
          "brain_invocation.execution_governance_payload_hash"
        ),
      gateway_request:
        attrs
        |> fetch!(:gateway_request, "brain_invocation.gateway_request")
        |> validate_json_object!("brain_invocation.gateway_request"),
      runtime_request:
        attrs
        |> fetch!(:runtime_request, "brain_invocation.runtime_request")
        |> validate_json_object!("brain_invocation.runtime_request"),
      boundary_request:
        attrs
        |> fetch!(:boundary_request, "brain_invocation.boundary_request")
        |> validate_json_object!("brain_invocation.boundary_request"),
      execution_intent_family:
        attrs
        |> fetch!(:execution_intent_family, "brain_invocation.execution_intent_family")
        |> validate_string!("brain_invocation.execution_intent_family"),
      execution_intent:
        attrs
        |> fetch!(:execution_intent, "brain_invocation.execution_intent")
        |> validate_json_object!("brain_invocation.execution_intent"),
      extensions:
        validate_json_object!(Map.get(attrs, :extensions, %{}), "brain_invocation.extensions")
    }
  end

  defp normalize(%__MODULE__{} = invocation) do
    {:ok, build!(dump(invocation))}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_contract_version!(value) when value == @contract_version, do: value

  defp validate_contract_version!(value) do
    raise ArgumentError,
          "brain_invocation.contract_version must be #{@contract_version}, got: #{inspect(value)}"
  end

  defp validate_submission_identity!(%SubmissionIdentity{} = identity),
    do: SubmissionIdentity.new!(identity)

  defp validate_submission_identity!(identity), do: SubmissionIdentity.new!(identity)

  defp validate_authority_payload!(%AuthorityAuditEnvelope{} = payload),
    do: AuthorityAuditEnvelope.new!(payload)

  defp validate_authority_payload!(payload), do: AuthorityAuditEnvelope.new!(payload)

  defp validate_governance_payload!(%ExecutionGovernanceProjection{} = payload),
    do: ExecutionGovernanceProjection.new!(payload)

  defp validate_governance_payload!(payload), do: ExecutionGovernanceProjection.new!(payload)

  defp validate_hash!(value, expected, field_name) do
    value = Contracts.validate_checksum!(value)

    if value == expected do
      value
    else
      raise ArgumentError,
            "#{field_name} must match canonical payload hash #{inspect(expected)}, got: #{inspect(value)}"
    end
  end

  defp validate_json_object!(value, field_name) do
    normalized = CanonicalJson.normalize!(value)

    if is_map(normalized) do
      normalized
    else
      raise ArgumentError, "#{field_name} must normalize to a JSON object"
    end
  end

  defp validate_string!(value, field_name),
    do: Contracts.validate_non_empty_string!(value, field_name)

  defp fetch!(map, key, field_name), do: Contracts.fetch_required!(map, key, field_name)
end
