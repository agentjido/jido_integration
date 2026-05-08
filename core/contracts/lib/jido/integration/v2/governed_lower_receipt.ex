defmodule Jido.Integration.V2.GovernedLowerReceipt do
  @moduledoc """
  Terminal lower receipt tied to a governed lower envelope.
  """

  alias Jido.Integration.V2.{Contracts, GovernedLowerEnvelope}

  @statuses [:succeeded, :failed, :denied, :cancelled, :timed_out]

  @fields [
    :contract_name,
    :lower_receipt_ref,
    :lower_request_ref,
    :lower_runtime_kind,
    :status,
    :tenant_ref,
    :subject_ref,
    :run_ref,
    :workflow_ref,
    :attempt_ref,
    :trace_id,
    :idempotency_key,
    :authority_ref,
    :authority_decision_hash,
    :capability_id,
    :action_id,
    :connector_ref,
    :connector_manifest_ref,
    :connector_manifest_hash,
    :capability_negotiation_ref,
    :policy_bundle_hash,
    :cedar_schema_hash,
    :script_hash,
    :workspace_ref,
    :target_ref,
    :artifact_refs,
    :event_refs,
    :observed_at,
    :extensions
  ]

  @required [
    :lower_receipt_ref,
    :lower_request_ref,
    :lower_runtime_kind,
    :status,
    :tenant_ref,
    :run_ref,
    :trace_id,
    :idempotency_key,
    :authority_ref,
    :authority_decision_hash,
    :capability_id
  ]

  @contract_name "JidoIntegration.GovernedLowerReceipt.v1"

  @enforce_keys @required
  defstruct @fields

  @type t :: %__MODULE__{}

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = receipt), do: normalize(receipt)

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
      {:ok, receipt} -> receipt
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec matches_envelope?(t(), GovernedLowerEnvelope.t()) :: boolean()
  def matches_envelope?(%__MODULE__{} = receipt, %GovernedLowerEnvelope{} = envelope) do
    receipt.lower_request_ref == envelope.lower_request_ref and
      receipt.lower_runtime_kind == envelope.lower_runtime_kind and
      receipt.tenant_ref == envelope.tenant_ref and
      receipt.run_ref == envelope.run_ref and
      receipt.trace_id == envelope.trace_id and
      receipt.idempotency_key == envelope.idempotency_key and
      receipt.authority_ref == envelope.authority_ref and
      receipt.authority_decision_hash == envelope.authority_decision_hash and
      receipt.capability_id == envelope.capability_id
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = receipt) do
    receipt
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

  defp normalize(%__MODULE__{} = receipt) do
    {:ok,
     %__MODULE__{
       receipt
       | contract_name: @contract_name,
         lower_receipt_ref: required_string(receipt.lower_receipt_ref, :lower_receipt_ref),
         lower_request_ref: required_string(receipt.lower_request_ref, :lower_request_ref),
         lower_runtime_kind: Contracts.validate_lower_runtime_kind!(receipt.lower_runtime_kind),
         status: Contracts.validate_enum_atomish!(receipt.status, @statuses, "status"),
         tenant_ref: required_string(receipt.tenant_ref, :tenant_ref),
         subject_ref: optional_string(receipt.subject_ref, :subject_ref),
         run_ref: required_string(receipt.run_ref, :run_ref),
         workflow_ref: optional_string(receipt.workflow_ref, :workflow_ref),
         attempt_ref: optional_string(receipt.attempt_ref, :attempt_ref),
         trace_id: required_string(receipt.trace_id, :trace_id),
         idempotency_key: required_string(receipt.idempotency_key, :idempotency_key),
         authority_ref: required_string(receipt.authority_ref, :authority_ref),
         authority_decision_hash:
           required_string(receipt.authority_decision_hash, :authority_decision_hash),
         capability_id: required_string(receipt.capability_id, :capability_id),
         action_id: optional_string(receipt.action_id, :action_id) || receipt.capability_id,
         connector_ref: optional_string(receipt.connector_ref, :connector_ref),
         connector_manifest_ref:
           optional_string(receipt.connector_manifest_ref, :connector_manifest_ref),
         connector_manifest_hash:
           optional_string(receipt.connector_manifest_hash, :connector_manifest_hash),
         capability_negotiation_ref:
           optional_string(receipt.capability_negotiation_ref, :capability_negotiation_ref),
         policy_bundle_hash: optional_string(receipt.policy_bundle_hash, :policy_bundle_hash),
         cedar_schema_hash: optional_string(receipt.cedar_schema_hash, :cedar_schema_hash),
         script_hash: optional_string(receipt.script_hash, :script_hash),
         workspace_ref: optional_string(receipt.workspace_ref, :workspace_ref),
         target_ref: optional_string(receipt.target_ref, :target_ref),
         artifact_refs: string_list(receipt.artifact_refs || [], :artifact_refs),
         event_refs: list(receipt.event_refs || [], :event_refs),
         extensions: map(receipt.extensions || %{}, :extensions)
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
