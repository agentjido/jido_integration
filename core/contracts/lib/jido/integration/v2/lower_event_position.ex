defmodule Jido.Integration.V2.LowerEventPosition do
  @moduledoc """
  Phase 4 lower-event position evidence contract.

  Contract: `JidoIntegration.LowerEventPosition.v1`.
  """

  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.Contracts

  @contract_name "JidoIntegration.LowerEventPosition.v1"
  @contract_version "1.0.0"
  @statuses [:accepted, :duplicate, :conflict]

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
    :lower_stream_ref,
    :lower_scope_ref,
    :event_ref,
    :expected_position,
    :actual_position,
    :dedupe_key,
    :position_status,
    :conflict_ref,
    :metadata
  ]

  @enforce_keys @fields -- [:principal_ref, :system_actor_ref, :conflict_ref]
  defstruct @fields

  @type position_status :: :accepted | :duplicate | :conflict
  @type t :: %__MODULE__{}

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec position_statuses() :: [position_status()]
  def position_statuses, do: @statuses

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
    principal_ref = optional_string(attrs, :principal_ref, "lower_event_position.principal_ref")

    system_actor_ref =
      optional_string(attrs, :system_actor_ref, "lower_event_position.system_actor_ref")

    validate_actor_pair!(principal_ref, system_actor_ref)

    evidence = %__MODULE__{
      contract_name:
        attrs
        |> Contracts.get(:contract_name, @contract_name)
        |> validate_literal!(@contract_name, "lower_event_position.contract_name"),
      contract_version:
        attrs
        |> Contracts.get(:contract_version, @contract_version)
        |> validate_literal!(@contract_version, "lower_event_position.contract_version"),
      tenant_ref: required_string(attrs, :tenant_ref, "lower_event_position.tenant_ref"),
      installation_ref:
        required_string(attrs, :installation_ref, "lower_event_position.installation_ref"),
      workspace_ref: required_string(attrs, :workspace_ref, "lower_event_position.workspace_ref"),
      project_ref: required_string(attrs, :project_ref, "lower_event_position.project_ref"),
      environment_ref:
        required_string(attrs, :environment_ref, "lower_event_position.environment_ref"),
      principal_ref: principal_ref,
      system_actor_ref: system_actor_ref,
      resource_ref: required_string(attrs, :resource_ref, "lower_event_position.resource_ref"),
      authority_packet_ref:
        required_string(attrs, :authority_packet_ref, "lower_event_position.authority_packet_ref"),
      permission_decision_ref:
        required_string(
          attrs,
          :permission_decision_ref,
          "lower_event_position.permission_decision_ref"
        ),
      idempotency_key:
        required_string(attrs, :idempotency_key, "lower_event_position.idempotency_key"),
      trace_id: required_string(attrs, :trace_id, "lower_event_position.trace_id"),
      correlation_id:
        required_string(attrs, :correlation_id, "lower_event_position.correlation_id"),
      release_manifest_ref:
        required_string(attrs, :release_manifest_ref, "lower_event_position.release_manifest_ref"),
      lower_stream_ref:
        required_string(attrs, :lower_stream_ref, "lower_event_position.lower_stream_ref"),
      lower_scope_ref:
        required_string(attrs, :lower_scope_ref, "lower_event_position.lower_scope_ref"),
      event_ref: required_string(attrs, :event_ref, "lower_event_position.event_ref"),
      expected_position:
        required_position(attrs, :expected_position, "lower_event_position.expected_position"),
      actual_position:
        required_position(attrs, :actual_position, "lower_event_position.actual_position"),
      dedupe_key: required_string(attrs, :dedupe_key, "lower_event_position.dedupe_key"),
      position_status:
        attrs
        |> Contracts.fetch_required!(:position_status, "lower_event_position.position_status")
        |> Contracts.validate_enum_atomish!(@statuses, "lower_event_position.position_status"),
      conflict_ref: optional_string(attrs, :conflict_ref, "lower_event_position.conflict_ref"),
      metadata:
        attrs
        |> Contracts.get(:metadata, %{})
        |> normalize_metadata!("lower_event_position.metadata")
    }

    validate_position_semantics!(evidence)
  end

  defp normalize(%__MODULE__{} = evidence) do
    {:ok, evidence |> dump() |> build!()}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_actor_pair!(nil, nil),
    do: raise(ArgumentError, "lower_event_position requires principal_ref or system_actor_ref")

  defp validate_actor_pair!(_principal_ref, _system_actor_ref), do: :ok

  defp validate_position_semantics!(%__MODULE__{position_status: :conflict, conflict_ref: nil}) do
    raise ArgumentError, "lower_event_position.conflict_ref is required for conflict status"
  end

  defp validate_position_semantics!(%__MODULE__{
         position_status: :conflict,
         expected_position: position,
         actual_position: position
       }) do
    raise ArgumentError, "lower_event_position conflict requires differing positions"
  end

  defp validate_position_semantics!(%__MODULE__{
         position_status: status,
         expected_position: expected,
         actual_position: actual
       })
       when status in [:accepted, :duplicate] and expected != actual do
    raise ArgumentError,
          "lower_event_position #{status} requires expected_position == actual_position"
  end

  defp validate_position_semantics!(%__MODULE__{} = evidence), do: evidence

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

  defp required_position(attrs, key, field_name) do
    value = Contracts.fetch_required!(attrs, key, field_name)

    if is_integer(value) and value >= 0 do
      value
    else
      raise ArgumentError, "#{field_name} must be a non-negative integer, got: #{inspect(value)}"
    end
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
