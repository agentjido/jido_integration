defmodule Jido.Integration.V2.GovernedLowerDenial do
  @moduledoc """
  Structured pre-effect or lower-effect denial tied to a governed envelope.
  """

  alias Jido.Integration.V2.{Contracts, GovernedLowerEnvelope}

  @denial_classes [
    :authority_denied,
    :policy_denied,
    :capability_denied,
    :manifest_missing,
    :manifest_stale,
    :manifest_invalid,
    :manifest_quarantined,
    :runtime_profile_incompatible,
    :resource_scope_unresolvable,
    :sandbox_downgrade,
    :attestation_mismatch,
    :attestation_unsatisfied,
    :policy_bundle_missing,
    :script_binding_invalid,
    :cedar_policy_denied,
    :lower_runtime_unsupported,
    :lower_runtime_unavailable,
    :lower_runtime_failed,
    :receipt_missing,
    :unsafe_retry,
    :retry_not_safe,
    :dispatch_failed
  ]

  @fields [
    :contract_name,
    :lower_denial_ref,
    :lower_request_ref,
    :lower_runtime_kind,
    :denial_class,
    :reason,
    :tenant_ref,
    :subject_ref,
    :run_ref,
    :workflow_ref,
    :attempt_ref,
    :trace_id,
    :authority_ref,
    :authority_decision_hash,
    :capability_id,
    :action_id,
    :connector_manifest_ref,
    :connector_manifest_hash,
    :capability_negotiation_ref,
    :policy_bundle_ref,
    :cedar_schema_ref,
    :script_ref,
    :resource_scope_refs,
    :sandbox_profile_ref,
    :attestation_ref,
    :extensions
  ]

  @required [
    :lower_denial_ref,
    :lower_request_ref,
    :lower_runtime_kind,
    :denial_class,
    :reason,
    :tenant_ref,
    :run_ref,
    :trace_id,
    :authority_ref,
    :authority_decision_hash,
    :capability_id
  ]

  @contract_name "JidoIntegration.GovernedLowerDenial.v1"

  @enforce_keys @required
  defstruct @fields

  @type t :: %__MODULE__{}

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = denial), do: normalize(denial)

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
      {:ok, denial} -> denial
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec matches_envelope?(t(), GovernedLowerEnvelope.t()) :: boolean()
  def matches_envelope?(%__MODULE__{} = denial, %GovernedLowerEnvelope{} = envelope) do
    denial.lower_request_ref == envelope.lower_request_ref and
      denial.lower_runtime_kind == envelope.lower_runtime_kind and
      denial.tenant_ref == envelope.tenant_ref and
      denial.run_ref == envelope.run_ref and
      denial.trace_id == envelope.trace_id and
      denial.authority_ref == envelope.authority_ref and
      denial.authority_decision_hash == envelope.authority_decision_hash and
      denial.capability_id == envelope.capability_id
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = denial) do
    denial
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

  defp normalize(%__MODULE__{} = denial) do
    {:ok,
     %__MODULE__{
       denial
       | contract_name: @contract_name,
         lower_denial_ref: required_string(denial.lower_denial_ref, :lower_denial_ref),
         lower_request_ref: required_string(denial.lower_request_ref, :lower_request_ref),
         lower_runtime_kind: Contracts.validate_lower_runtime_kind!(denial.lower_runtime_kind),
         denial_class:
           Contracts.validate_enum_atomish!(denial.denial_class, @denial_classes, "denial_class"),
         reason: required_string(denial.reason, :reason),
         tenant_ref: required_string(denial.tenant_ref, :tenant_ref),
         subject_ref: optional_string(denial.subject_ref, :subject_ref),
         run_ref: required_string(denial.run_ref, :run_ref),
         workflow_ref: optional_string(denial.workflow_ref, :workflow_ref),
         attempt_ref: optional_string(denial.attempt_ref, :attempt_ref),
         trace_id: required_string(denial.trace_id, :trace_id),
         authority_ref: required_string(denial.authority_ref, :authority_ref),
         authority_decision_hash:
           required_string(denial.authority_decision_hash, :authority_decision_hash),
         capability_id: required_string(denial.capability_id, :capability_id),
         action_id: optional_string(denial.action_id, :action_id) || denial.capability_id,
         connector_manifest_ref:
           optional_string(denial.connector_manifest_ref, :connector_manifest_ref),
         connector_manifest_hash:
           optional_string(denial.connector_manifest_hash, :connector_manifest_hash),
         capability_negotiation_ref:
           optional_string(denial.capability_negotiation_ref, :capability_negotiation_ref),
         policy_bundle_ref: optional_string(denial.policy_bundle_ref, :policy_bundle_ref),
         cedar_schema_ref: optional_string(denial.cedar_schema_ref, :cedar_schema_ref),
         script_ref: optional_string(denial.script_ref, :script_ref),
         resource_scope_refs: string_list(denial.resource_scope_refs || [], :resource_scope_refs),
         sandbox_profile_ref: optional_string(denial.sandbox_profile_ref, :sandbox_profile_ref),
         attestation_ref: optional_string(denial.attestation_ref, :attestation_ref),
         extensions: map(denial.extensions || %{}, :extensions)
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp field_value(attrs, field), do: Map.get(attrs, field, Map.get(attrs, Atom.to_string(field)))

  defp required_string(value, field) do
    value
    |> Contracts.validate_non_empty_string!(Atom.to_string(field))
    |> String.trim()
  end

  defp optional_string(nil, _field), do: nil
  defp optional_string("", _field), do: nil
  defp optional_string(value, field), do: required_string(value, field)

  defp string_list(values, field) when is_list(values) do
    Enum.map(values, &required_string(&1, field))
  end

  defp string_list(values, field) do
    raise ArgumentError, "#{field} must be a list of non-empty strings, got: #{inspect(values)}"
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
