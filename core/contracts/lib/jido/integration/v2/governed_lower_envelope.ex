defmodule Jido.Integration.V2.GovernedLowerEnvelope do
  @moduledoc """
  Governed lower-effect envelope shared by deterministic, connector, session,
  and future TRE lower lanes.

  This contract is intentionally distinct from the existing backend
  `runtime_kind` field (`:client | :task | :service`). `lower_runtime_kind`
  describes the lower execution lane selected for one governed effect.
  """

  alias Jido.Integration.V2.Contracts

  @manifest_states [:active, :stale, :invalid, :refresh_required, :quarantined]
  @side_effect_classes [:read, :write, :execute]
  @idempotency_classes [:idempotent, :non_idempotent]
  @runtime_classes [:direct, :session, :stream, :fixture]
  @dispatchable_kinds [:deterministic_fixture, :codex_session, :direct_connector]

  @fields [
    :contract_name,
    :lower_request_ref,
    :lower_runtime_kind,
    :runtime_profile_ref,
    :runtime_profile_kind,
    :capability_id,
    :action_id,
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
    :connector_ref,
    :connector_manifest_ref,
    :connector_manifest_hash,
    :connector_manifest_state,
    :capability_negotiation_ref,
    :side_effect_class,
    :idempotency_class,
    :runtime_class,
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
    :input_hash,
    :extensions
  ]

  @required [
    :lower_request_ref,
    :lower_runtime_kind,
    :runtime_profile_ref,
    :runtime_profile_kind,
    :capability_id,
    :tenant_ref,
    :run_ref,
    :trace_id,
    :idempotency_key,
    :authority_ref,
    :authority_decision_hash,
    :allowed_operations
  ]

  @contract_name "JidoIntegration.GovernedLowerEnvelope.v1"

  @enforce_keys @required
  defstruct @fields

  @type t :: %__MODULE__{}

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = envelope), do: normalize(envelope)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs
    |> build()
    |> normalize()
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, envelope} -> envelope
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec dispatchable?(t()) :: boolean()
  def dispatchable?(%__MODULE__{lower_runtime_kind: lower_runtime_kind}) do
    lower_runtime_kind in @dispatchable_kinds
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = envelope) do
    envelope
    |> Map.from_struct()
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), serialize(value)} end)
  end

  defp build(attrs) do
    attrs = Map.new(attrs)

    struct!(
      __MODULE__,
      for field <- @fields, into: %{} do
        {field, field_value(attrs, field)}
      end
    )
  end

  defp normalize(%__MODULE__{} = envelope) do
    normalized = %__MODULE__{
      envelope
      | contract_name: @contract_name,
        lower_request_ref: required_string(envelope.lower_request_ref, :lower_request_ref),
        lower_runtime_kind: Contracts.validate_lower_runtime_kind!(envelope.lower_runtime_kind),
        runtime_profile_ref: required_string(envelope.runtime_profile_ref, :runtime_profile_ref),
        runtime_profile_kind:
          required_atomish(envelope.runtime_profile_kind, :runtime_profile_kind),
        capability_id: required_string(envelope.capability_id, :capability_id),
        action_id: optional_string(envelope.action_id, :action_id) || envelope.capability_id,
        tenant_ref: required_string(envelope.tenant_ref, :tenant_ref),
        subject_ref: optional_string(envelope.subject_ref, :subject_ref),
        run_ref: required_string(envelope.run_ref, :run_ref),
        workflow_ref: optional_string(envelope.workflow_ref, :workflow_ref),
        attempt_ref: optional_string(envelope.attempt_ref, :attempt_ref),
        trace_id: required_string(envelope.trace_id, :trace_id),
        idempotency_key: required_string(envelope.idempotency_key, :idempotency_key),
        authority_ref: required_string(envelope.authority_ref, :authority_ref),
        authority_decision_hash:
          required_string(envelope.authority_decision_hash, :authority_decision_hash),
        allowed_operations: string_list(envelope.allowed_operations, :allowed_operations),
        connector_ref: optional_string(envelope.connector_ref, :connector_ref),
        connector_manifest_ref:
          optional_string(envelope.connector_manifest_ref, :connector_manifest_ref),
        connector_manifest_hash:
          optional_string(envelope.connector_manifest_hash, :connector_manifest_hash),
        connector_manifest_state:
          optional_enumish(
            envelope.connector_manifest_state,
            @manifest_states,
            :connector_manifest_state
          ),
        capability_negotiation_ref:
          optional_string(envelope.capability_negotiation_ref, :capability_negotiation_ref),
        side_effect_class:
          optional_enumish(envelope.side_effect_class, @side_effect_classes, :side_effect_class),
        idempotency_class:
          optional_enumish(envelope.idempotency_class, @idempotency_classes, :idempotency_class),
        runtime_class: optional_enumish(envelope.runtime_class, @runtime_classes, :runtime_class),
        policy_profile_ref: optional_string(envelope.policy_profile_ref, :policy_profile_ref),
        policy_bundle_ref: optional_string(envelope.policy_bundle_ref, :policy_bundle_ref),
        policy_bundle_hash: optional_string(envelope.policy_bundle_hash, :policy_bundle_hash),
        cedar_schema_ref: optional_string(envelope.cedar_schema_ref, :cedar_schema_ref),
        cedar_schema_hash: optional_string(envelope.cedar_schema_hash, :cedar_schema_hash),
        script_ref: optional_string(envelope.script_ref, :script_ref),
        script_hash: optional_string(envelope.script_hash, :script_hash),
        script_api_version: optional_string(envelope.script_api_version, :script_api_version),
        declared_actions: string_list(envelope.declared_actions || [], :declared_actions),
        package_refs: string_list(envelope.package_refs || [], :package_refs),
        resource_scope_refs:
          string_list(envelope.resource_scope_refs || [], :resource_scope_refs),
        workspace_ref: optional_string(envelope.workspace_ref, :workspace_ref),
        target_ref: optional_string(envelope.target_ref, :target_ref),
        placement_ref: optional_string(envelope.placement_ref, :placement_ref),
        sandbox_profile_ref: optional_string(envelope.sandbox_profile_ref, :sandbox_profile_ref),
        sandbox_level:
          optional_enumish(
            envelope.sandbox_level,
            [:strict, :standard, :none, :process, :container, :microvm],
            :sandbox_level
          ),
        network_policy_ref: optional_string(envelope.network_policy_ref, :network_policy_ref),
        filesystem_policy_ref:
          optional_string(envelope.filesystem_policy_ref, :filesystem_policy_ref),
        acceptable_attestation:
          list(envelope.acceptable_attestation || [], :acceptable_attestation),
        attestation_requirement_ref:
          optional_string(envelope.attestation_requirement_ref, :attestation_requirement_ref),
        evidence_profile_ref:
          optional_string(envelope.evidence_profile_ref, :evidence_profile_ref),
        redaction_profile_ref:
          optional_string(envelope.redaction_profile_ref, :redaction_profile_ref),
        input_ref: optional_string(envelope.input_ref, :input_ref),
        input_hash: optional_string(envelope.input_hash, :input_hash),
        extensions: map(envelope.extensions || %{}, :extensions)
    }

    with :ok <- require_allowed_operation(normalized),
         :ok <- require_active_manifest_for_unsafe_write(normalized) do
      {:ok, normalized}
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp require_allowed_operation(%__MODULE__{} = envelope) do
    if envelope.capability_id in envelope.allowed_operations do
      :ok
    else
      {:error,
       ArgumentError.exception(
         "allowed_operations must include capability_id #{inspect(envelope.capability_id)}"
       )}
    end
  end

  defp require_active_manifest_for_unsafe_write(%__MODULE__{
         side_effect_class: :write,
         idempotency_class: :non_idempotent,
         connector_manifest_state: state
       })
       when state != :active do
    {:error,
     ArgumentError.exception(
       "non-idempotent writes require an active connector manifest before lower dispatch"
     )}
  end

  defp require_active_manifest_for_unsafe_write(_envelope), do: :ok

  defp field_value(attrs, field), do: Map.get(attrs, field, Map.get(attrs, Atom.to_string(field)))

  defp required_string(value, field) do
    value
    |> Contracts.validate_non_empty_string!(Atom.to_string(field))
    |> String.trim()
  end

  defp optional_string(nil, _field), do: nil
  defp optional_string("", _field), do: nil

  defp optional_string(value, field) do
    required_string(value, field)
  end

  defp required_atomish(value, field) do
    case value do
      atom when is_atom(atom) ->
        atom

      binary when is_binary(binary) ->
        Contracts.validate_non_empty_string!(binary, Atom.to_string(field))

      other ->
        raise ArgumentError,
              "#{field} must be an atom or non-empty string, got: #{inspect(other)}"
    end
  end

  defp optional_enumish(nil, _values, _field), do: nil

  defp optional_enumish(value, values, field) do
    Contracts.validate_enum_atomish!(value, values, Atom.to_string(field))
  end

  defp string_list(values, field) when is_list(values) do
    Enum.map(values, &required_string(&1, field))
  end

  defp string_list(values, field) do
    raise ArgumentError, "#{field} must be a list of non-empty strings, got: #{inspect(values)}"
  end

  defp list(values, _field) when is_list(values), do: values

  defp list(values, field) do
    raise ArgumentError, "#{field} must be a list, got: #{inspect(values)}"
  end

  defp map(value, _field) when is_map(value), do: value

  defp map(value, field) do
    raise ArgumentError, "#{field} must be a map, got: #{inspect(value)}"
  end

  defp serialize(value) when is_atom(value), do: Atom.to_string(value)
  defp serialize(values) when is_list(values), do: Enum.map(values, &serialize/1)

  defp serialize(%{} = map),
    do: Map.new(map, fn {key, value} -> {serialize(key), serialize(value)} end)

  defp serialize(value), do: value
end
