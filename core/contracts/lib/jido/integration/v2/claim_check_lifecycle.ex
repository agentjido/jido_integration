defmodule Jido.Integration.V2.ClaimCheckLifecycle do
  @moduledoc """
  Phase 4 claim-check lifecycle and quarantine evidence contract.

  Contract: `JidoIntegration.ClaimCheckLifecycle.v1`.
  """

  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.Contracts

  @contract_name "JidoIntegration.ClaimCheckLifecycle.v1"
  @contract_version "1.0.0"
  @lifecycle_states [:active, :quarantined, :gc_eligible, :deleted]
  @retention_classes [:short_lived, :workflow_run, :audit_retained, :legal_hold]
  @quarantine_reasons [
    :missing_payload,
    :oversized_payload,
    :stale_payload,
    :schema_invalid,
    :unowned_payload,
    :hash_mismatch
  ]

  @fields [
    :contract_name,
    :contract_version,
    :tenant_ref,
    :installation_ref,
    :workspace_ref,
    :project_ref,
    :environment_ref,
    :principal_ref,
    :system_actor_ref,
    :resource_ref,
    :authority_packet_ref,
    :permission_decision_ref,
    :idempotency_key,
    :trace_id,
    :correlation_id,
    :release_manifest_ref,
    :claim_check_ref,
    :payload_hash,
    :schema_ref,
    :size_bytes,
    :retention_class,
    :lifecycle_state,
    :quarantine_reason,
    :gc_after_at,
    :metadata
  ]

  @enforce_keys @fields -- [:principal_ref, :system_actor_ref, :quarantine_reason]
  defstruct @fields

  @type lifecycle_state :: :active | :quarantined | :gc_eligible | :deleted
  @type retention_class :: :short_lived | :workflow_run | :audit_retained | :legal_hold
  @type quarantine_reason ::
          :missing_payload
          | :oversized_payload
          | :stale_payload
          | :schema_invalid
          | :unowned_payload
          | :hash_mismatch
  @type t :: %__MODULE__{}

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec lifecycle_states() :: [lifecycle_state()]
  def lifecycle_states, do: @lifecycle_states

  @spec retention_classes() :: [retention_class()]
  def retention_classes, do: @retention_classes

  @spec quarantine_reasons() :: [quarantine_reason()]
  def quarantine_reasons, do: @quarantine_reasons

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = evidence), do: normalize(evidence)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = evidence) do
    case normalize(evidence) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = evidence) do
    @fields
    |> Map.new(&{&1, Map.fetch!(evidence, &1)})
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp build!(attrs) do
    attrs = Map.new(attrs)
    principal_ref = optional_string(attrs, :principal_ref, "claim_check_lifecycle.principal_ref")

    system_actor_ref =
      optional_string(attrs, :system_actor_ref, "claim_check_lifecycle.system_actor_ref")

    validate_actor_pair!(principal_ref, system_actor_ref)

    evidence = %__MODULE__{
      contract_name:
        attrs
        |> Contracts.get(:contract_name, @contract_name)
        |> validate_literal!(@contract_name, "claim_check_lifecycle.contract_name"),
      contract_version:
        attrs
        |> Contracts.get(:contract_version, @contract_version)
        |> validate_literal!(@contract_version, "claim_check_lifecycle.contract_version"),
      tenant_ref: required_string(attrs, :tenant_ref, "claim_check_lifecycle.tenant_ref"),
      installation_ref:
        required_string(attrs, :installation_ref, "claim_check_lifecycle.installation_ref"),
      workspace_ref:
        required_string(attrs, :workspace_ref, "claim_check_lifecycle.workspace_ref"),
      project_ref: required_string(attrs, :project_ref, "claim_check_lifecycle.project_ref"),
      environment_ref:
        required_string(attrs, :environment_ref, "claim_check_lifecycle.environment_ref"),
      principal_ref: principal_ref,
      system_actor_ref: system_actor_ref,
      resource_ref: required_string(attrs, :resource_ref, "claim_check_lifecycle.resource_ref"),
      authority_packet_ref:
        required_string(
          attrs,
          :authority_packet_ref,
          "claim_check_lifecycle.authority_packet_ref"
        ),
      permission_decision_ref:
        required_string(
          attrs,
          :permission_decision_ref,
          "claim_check_lifecycle.permission_decision_ref"
        ),
      idempotency_key:
        required_string(attrs, :idempotency_key, "claim_check_lifecycle.idempotency_key"),
      trace_id: required_string(attrs, :trace_id, "claim_check_lifecycle.trace_id"),
      correlation_id:
        required_string(attrs, :correlation_id, "claim_check_lifecycle.correlation_id"),
      release_manifest_ref:
        required_string(
          attrs,
          :release_manifest_ref,
          "claim_check_lifecycle.release_manifest_ref"
        ),
      claim_check_ref:
        required_string(attrs, :claim_check_ref, "claim_check_lifecycle.claim_check_ref"),
      payload_hash:
        attrs
        |> Contracts.fetch_required!(:payload_hash, "claim_check_lifecycle.payload_hash")
        |> Contracts.validate_checksum!(),
      schema_ref: required_string(attrs, :schema_ref, "claim_check_lifecycle.schema_ref"),
      size_bytes: required_size(attrs, :size_bytes, "claim_check_lifecycle.size_bytes"),
      retention_class:
        attrs
        |> Contracts.fetch_required!(:retention_class, "claim_check_lifecycle.retention_class")
        |> Contracts.validate_enum_atomish!(
          @retention_classes,
          "claim_check_lifecycle.retention_class"
        ),
      lifecycle_state:
        attrs
        |> Contracts.fetch_required!(:lifecycle_state, "claim_check_lifecycle.lifecycle_state")
        |> Contracts.validate_enum_atomish!(
          @lifecycle_states,
          "claim_check_lifecycle.lifecycle_state"
        ),
      quarantine_reason:
        optional_quarantine_reason(
          attrs,
          :quarantine_reason,
          "claim_check_lifecycle.quarantine_reason"
        ),
      gc_after_at:
        attrs
        |> Contracts.fetch_required!(:gc_after_at, "claim_check_lifecycle.gc_after_at")
        |> validate_datetime!("claim_check_lifecycle.gc_after_at"),
      metadata:
        attrs
        |> Contracts.get(:metadata, %{})
        |> normalize_metadata!("claim_check_lifecycle.metadata")
    }

    validate_quarantine_semantics!(evidence)
  end

  defp normalize(%__MODULE__{} = evidence) do
    {:ok, evidence |> dump() |> build!()}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_actor_pair!(nil, nil),
    do: raise(ArgumentError, "claim_check_lifecycle requires principal_ref or system_actor_ref")

  defp validate_actor_pair!(_principal_ref, _system_actor_ref), do: :ok

  defp validate_quarantine_semantics!(%__MODULE__{
         lifecycle_state: :quarantined,
         quarantine_reason: nil
       }) do
    raise ArgumentError,
          "claim_check_lifecycle.quarantine_reason is required for quarantined state"
  end

  defp validate_quarantine_semantics!(%__MODULE__{} = evidence), do: evidence

  defp required_string(attrs, key, field_name) do
    attrs
    |> Contracts.fetch_required!(key, field_name)
    |> Contracts.validate_non_empty_string!(field_name)
  end

  defp optional_string(attrs, key, field_name) do
    case Contracts.get(attrs, key) do
      nil -> nil
      value -> Contracts.validate_non_empty_string!(value, field_name)
    end
  end

  defp required_size(attrs, key, field_name) do
    value = Contracts.fetch_required!(attrs, key, field_name)

    if is_integer(value) and value >= 0 do
      value
    else
      raise ArgumentError, "#{field_name} must be a non-negative integer, got: #{inspect(value)}"
    end
  end

  defp optional_quarantine_reason(attrs, key, field_name) do
    case Contracts.get(attrs, key) do
      nil -> nil
      value -> Contracts.validate_enum_atomish!(value, @quarantine_reasons, field_name)
    end
  end

  defp validate_datetime!(%DateTime{} = value, _field_name), do: value

  defp validate_datetime!(value, field_name) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> raise ArgumentError, "#{field_name} must be ISO-8601"
    end
  end

  defp validate_datetime!(value, field_name) do
    raise ArgumentError, "#{field_name} must be DateTime or ISO-8601, got: #{inspect(value)}"
  end

  defp validate_literal!(value, expected, _field_name) when value == expected, do: value

  defp validate_literal!(value, expected, field_name) do
    raise ArgumentError, "#{field_name} must be #{expected}, got: #{inspect(value)}"
  end

  defp normalize_metadata!(value, field_name) do
    normalized = CanonicalJson.normalize!(value)

    if is_map(normalized) do
      normalized
    else
      raise ArgumentError, "#{field_name} must normalize to a JSON object"
    end
  end
end
