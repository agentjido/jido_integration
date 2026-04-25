defmodule Jido.Integration.V2.ExecutionGovernanceProjection do
  @moduledoc """
  lower-gateway-owned machine-readable governance projection carried in Brain submissions.
  """

  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.Contracts

  @contract_version "v1"
  @sandbox_levels ["strict", "standard", "none"]
  @egress_policies ["blocked", "restricted", "open"]
  @approval_modes ["manual", "auto", "none"]
  @workspace_mutabilities ["read_only", "read_write", "ephemeral"]
  @execution_families ["process", "http", "json_rpc", "service"]
  @placement_intents ["host_local", "remote_scope", "remote_workspace", "ephemeral_session"]
  @session_modes ["attached", "detached", "stateless"]
  @coordination_modes ["single_target", "parallel_fanout", "local_only"]

  @type t :: %__MODULE__{
          contract_version: String.t(),
          execution_governance_id: String.t(),
          authority_ref: map(),
          sandbox: map(),
          boundary: map(),
          topology: map(),
          workspace: map(),
          resources: map(),
          placement: map(),
          operations: map(),
          extensions: map()
        }

  @enforce_keys [
    :contract_version,
    :execution_governance_id,
    :authority_ref,
    :sandbox,
    :boundary,
    :topology,
    :workspace,
    :resources,
    :placement,
    :operations,
    :extensions
  ]
  defstruct @enforce_keys

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = projection), do: normalize(projection)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = projection) do
    case normalize(projection) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = projection) do
    %{
      contract_version: projection.contract_version,
      execution_governance_id: projection.execution_governance_id,
      authority_ref: projection.authority_ref,
      sandbox: projection.sandbox,
      boundary: projection.boundary,
      topology: projection.topology,
      workspace: projection.workspace,
      resources: projection.resources,
      placement: projection.placement,
      operations: projection.operations,
      extensions: projection.extensions
    }
  end

  @spec payload_hash(t()) :: Contracts.checksum()
  def payload_hash(%__MODULE__{} = projection) do
    projection
    |> dump()
    |> CanonicalJson.checksum!()
  end

  defp build!(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      contract_version:
        validate_contract_version!(Map.get(attrs, :contract_version, @contract_version)),
      execution_governance_id:
        attrs
        |> fetch!(:execution_governance_id, "execution_governance.execution_governance_id")
        |> validate_string!("execution_governance.execution_governance_id"),
      authority_ref:
        attrs
        |> fetch!(:authority_ref, "execution_governance.authority_ref")
        |> validate_authority_ref!(),
      sandbox:
        attrs
        |> fetch!(:sandbox, "execution_governance.sandbox")
        |> validate_sandbox!(),
      boundary:
        attrs
        |> fetch!(:boundary, "execution_governance.boundary")
        |> validate_boundary!(),
      topology:
        attrs
        |> fetch!(:topology, "execution_governance.topology")
        |> validate_topology!(),
      workspace:
        attrs
        |> fetch!(:workspace, "execution_governance.workspace")
        |> validate_workspace!(),
      resources:
        attrs
        |> fetch!(:resources, "execution_governance.resources")
        |> validate_resources!(),
      placement:
        attrs
        |> fetch!(:placement, "execution_governance.placement")
        |> validate_placement!(),
      operations:
        attrs
        |> fetch!(:operations, "execution_governance.operations")
        |> validate_operations!(),
      extensions: validate_extensions!(Map.get(attrs, :extensions, %{}))
    }
  end

  defp normalize(%__MODULE__{} = projection) do
    {:ok, build!(dump(projection))}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_contract_version!(value) when value == @contract_version, do: value

  defp validate_contract_version!(value) do
    raise ArgumentError,
          "execution_governance.contract_version must be #{@contract_version}, got: #{inspect(value)}"
  end

  defp validate_authority_ref!(value) do
    normalized = validate_json_object!(value, "execution_governance.authority_ref")

    %{
      "decision_id" => required_object_string!(normalized, "decision_id", "authority_ref"),
      "policy_version" => required_object_string!(normalized, "policy_version", "authority_ref"),
      "decision_hash" => required_object_string!(normalized, "decision_hash", "authority_ref")
    }
  end

  defp validate_sandbox!(value) do
    normalized = validate_json_object!(value, "execution_governance.sandbox")

    %{
      "level" => required_enum!(normalized, "level", @sandbox_levels, "sandbox"),
      "egress" => required_enum!(normalized, "egress", @egress_policies, "sandbox"),
      "approvals" => required_enum!(normalized, "approvals", @approval_modes, "sandbox"),
      "acceptable_attestation" =>
        required_non_empty_string_list!(normalized, "acceptable_attestation", "sandbox"),
      "allowed_tools" => required_string_list!(normalized, "allowed_tools", "sandbox"),
      "file_scope_ref" => required_object_string!(normalized, "file_scope_ref", "sandbox"),
      "file_scope_hint" => optional_object_string(normalized, "file_scope_hint", "sandbox")
    }
  end

  defp validate_boundary!(value) do
    normalized = validate_json_object!(value, "execution_governance.boundary")

    %{
      "boundary_class" => required_object_string!(normalized, "boundary_class", "boundary"),
      "trust_profile" => required_object_string!(normalized, "trust_profile", "boundary"),
      "requested_attach_mode" =>
        required_object_string!(normalized, "requested_attach_mode", "boundary"),
      "requested_ttl_ms" =>
        required_object_non_neg_integer!(normalized, "requested_ttl_ms", "boundary")
    }
  end

  defp validate_topology!(value) do
    normalized = validate_json_object!(value, "execution_governance.topology")

    %{
      "topology_intent_id" =>
        required_object_string!(normalized, "topology_intent_id", "topology"),
      "session_mode" => required_enum!(normalized, "session_mode", @session_modes, "topology"),
      "coordination_mode" =>
        required_enum!(normalized, "coordination_mode", @coordination_modes, "topology"),
      "topology_epoch" =>
        required_object_non_neg_integer!(normalized, "topology_epoch", "topology"),
      "routing_hints" => required_object_json_object!(normalized, "routing_hints", "topology")
    }
  end

  defp validate_workspace!(value) do
    normalized = validate_json_object!(value, "execution_governance.workspace")

    %{
      "workspace_profile" =>
        required_object_string!(normalized, "workspace_profile", "workspace"),
      "logical_workspace_ref" =>
        required_object_string!(normalized, "logical_workspace_ref", "workspace"),
      "mutability" =>
        required_enum!(normalized, "mutability", @workspace_mutabilities, "workspace")
    }
  end

  defp validate_resources!(value) do
    normalized = validate_json_object!(value, "execution_governance.resources")

    %{
      "resource_profile" => required_object_string!(normalized, "resource_profile", "resources"),
      "cpu_class" => optional_object_string(normalized, "cpu_class", "resources"),
      "memory_class" => optional_object_string(normalized, "memory_class", "resources"),
      "wall_clock_budget_ms" =>
        optional_object_non_neg_integer(normalized, "wall_clock_budget_ms", "resources")
    }
  end

  defp validate_placement!(value) do
    normalized = validate_json_object!(value, "execution_governance.placement")

    %{
      "execution_family" =>
        required_enum!(normalized, "execution_family", @execution_families, "placement"),
      "placement_intent" =>
        required_enum!(normalized, "placement_intent", @placement_intents, "placement"),
      "target_kind" => required_object_string!(normalized, "target_kind", "placement"),
      "node_affinity" => optional_object_string(normalized, "node_affinity", "placement")
    }
  end

  defp validate_operations!(value) do
    normalized = validate_json_object!(value, "execution_governance.operations")

    %{
      "allowed_operations" =>
        required_non_empty_string_list!(normalized, "allowed_operations", "operations"),
      "effect_classes" => required_string_list!(normalized, "effect_classes", "operations")
    }
  end

  defp validate_extensions!(value) do
    normalized = CanonicalJson.normalize!(value)

    if is_map(normalized) do
      normalized
    else
      raise ArgumentError, "execution_governance.extensions must normalize to a JSON object"
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

  defp required_object_json_object!(map, key, field_name) do
    map
    |> required_object_value!(key, field_name)
    |> validate_json_object!("#{field_name}.#{key}")
  end

  defp required_object_string!(map, key, field_name) do
    map
    |> required_object_value!(key, field_name)
    |> validate_string!("#{field_name}.#{key}")
  end

  defp optional_object_string(map, key, field_name) do
    case Map.get(map, key) do
      nil -> nil
      value -> validate_string!(value, "#{field_name}.#{key}")
    end
  end

  defp required_object_non_neg_integer!(map, key, field_name) do
    value = required_object_value!(map, key, field_name)
    validate_non_neg_integer!(value, "#{field_name}.#{key}")
  end

  defp optional_object_non_neg_integer(map, key, field_name) do
    case Map.get(map, key) do
      nil -> nil
      value -> validate_non_neg_integer!(value, "#{field_name}.#{key}")
    end
  end

  defp required_enum!(map, key, allowed, field_name) do
    value = required_object_string!(map, key, field_name)

    if value in allowed do
      value
    else
      raise ArgumentError,
            "#{field_name}.#{key} must be one of #{inspect(allowed)}, got: #{inspect(value)}"
    end
  end

  defp required_string_list!(map, key, field_name) do
    map
    |> required_object_value!(key, field_name)
    |> Contracts.normalize_string_list!("#{field_name}.#{key}")
  end

  defp required_non_empty_string_list!(map, key, field_name) do
    values = required_string_list!(map, key, field_name)

    if values == [] do
      raise ArgumentError, "#{field_name}.#{key} must not be empty"
    end

    values
  end

  defp required_object_value!(map, key, field_name) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "#{field_name}.#{key} is required"
    end
  end

  defp validate_string!(value, field_name),
    do: Contracts.validate_non_empty_string!(value, field_name)

  defp validate_non_neg_integer!(value, _field_name) when is_integer(value) and value >= 0,
    do: value

  defp validate_non_neg_integer!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a non-negative integer, got: #{inspect(value)}"
  end

  defp fetch!(map, key, field_name), do: Contracts.fetch_required!(map, key, field_name)
end
