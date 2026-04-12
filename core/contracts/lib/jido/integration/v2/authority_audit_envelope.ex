defmodule Jido.Integration.V2.AuthorityAuditEnvelope do
  @moduledoc """
  Spine-owned machine-readable authority audit payload derived from the Brain packet.
  """

  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.Contracts

  @contract_version "v1"
  @decision_hash_regex ~r/\A[0-9a-f]{64}\z/

  @type t :: %__MODULE__{
          contract_version: String.t(),
          decision_id: String.t(),
          tenant_id: String.t(),
          request_id: String.t(),
          policy_version: String.t(),
          boundary_class: String.t(),
          trust_profile: String.t(),
          approval_profile: String.t(),
          egress_profile: String.t(),
          workspace_profile: String.t(),
          resource_profile: String.t(),
          decision_hash: String.t(),
          extensions: map()
        }

  @enforce_keys [
    :contract_version,
    :decision_id,
    :tenant_id,
    :request_id,
    :policy_version,
    :boundary_class,
    :trust_profile,
    :approval_profile,
    :egress_profile,
    :workspace_profile,
    :resource_profile,
    :decision_hash,
    :extensions
  ]
  defstruct @enforce_keys

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = payload), do: normalize(payload)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = payload) do
    case normalize(payload) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = payload) do
    %{
      contract_version: payload.contract_version,
      decision_id: payload.decision_id,
      tenant_id: payload.tenant_id,
      request_id: payload.request_id,
      policy_version: payload.policy_version,
      boundary_class: payload.boundary_class,
      trust_profile: payload.trust_profile,
      approval_profile: payload.approval_profile,
      egress_profile: payload.egress_profile,
      workspace_profile: payload.workspace_profile,
      resource_profile: payload.resource_profile,
      decision_hash: payload.decision_hash,
      extensions: payload.extensions
    }
  end

  @spec payload_hash(t()) :: Contracts.checksum()
  def payload_hash(%__MODULE__{} = payload) do
    payload
    |> dump()
    |> CanonicalJson.checksum!()
  end

  defp build!(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      contract_version:
        validate_contract_version!(Map.get(attrs, :contract_version, @contract_version)),
      decision_id:
        attrs
        |> fetch!(:decision_id, "authority_audit.decision_id")
        |> validate_string!("authority_audit.decision_id"),
      tenant_id:
        attrs
        |> fetch!(:tenant_id, "authority_audit.tenant_id")
        |> validate_string!("authority_audit.tenant_id"),
      request_id:
        attrs
        |> fetch!(:request_id, "authority_audit.request_id")
        |> validate_string!("authority_audit.request_id"),
      policy_version:
        attrs
        |> fetch!(:policy_version, "authority_audit.policy_version")
        |> validate_string!("authority_audit.policy_version"),
      boundary_class:
        attrs
        |> fetch!(:boundary_class, "authority_audit.boundary_class")
        |> validate_string!("authority_audit.boundary_class"),
      trust_profile:
        attrs
        |> fetch!(:trust_profile, "authority_audit.trust_profile")
        |> validate_string!("authority_audit.trust_profile"),
      approval_profile:
        attrs
        |> fetch!(:approval_profile, "authority_audit.approval_profile")
        |> validate_string!("authority_audit.approval_profile"),
      egress_profile:
        attrs
        |> fetch!(:egress_profile, "authority_audit.egress_profile")
        |> validate_string!("authority_audit.egress_profile"),
      workspace_profile:
        attrs
        |> fetch!(:workspace_profile, "authority_audit.workspace_profile")
        |> validate_string!("authority_audit.workspace_profile"),
      resource_profile:
        attrs
        |> fetch!(:resource_profile, "authority_audit.resource_profile")
        |> validate_string!("authority_audit.resource_profile"),
      decision_hash:
        attrs
        |> fetch!(:decision_hash, "authority_audit.decision_hash")
        |> validate_decision_hash!(),
      extensions: validate_extensions!(Map.get(attrs, :extensions, %{}))
    }
  end

  defp normalize(%__MODULE__{} = payload) do
    {:ok, build!(dump(payload))}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_contract_version!(value) when value == @contract_version, do: value

  defp validate_contract_version!(value) do
    raise ArgumentError,
          "authority_audit.contract_version must be #{@contract_version}, got: #{inspect(value)}"
  end

  defp validate_string!(value, field_name),
    do: Contracts.validate_non_empty_string!(value, field_name)

  defp validate_decision_hash!(value) when is_binary(value) do
    if Regex.match?(@decision_hash_regex, value) do
      value
    else
      raise ArgumentError,
            "authority_audit.decision_hash must be lowercase SHA-256 hex, got: #{inspect(value)}"
    end
  end

  defp validate_decision_hash!(value) do
    raise ArgumentError,
          "authority_audit.decision_hash must be lowercase SHA-256 hex, got: #{inspect(value)}"
  end

  defp validate_extensions!(value) do
    normalized = CanonicalJson.normalize!(value)

    if is_map(normalized) do
      normalized
    else
      raise ArgumentError, "authority_audit.extensions must normalize to a JSON object"
    end
  end

  defp fetch!(map, key, field_name) do
    Contracts.fetch!(map, key)
  rescue
    KeyError -> raise ArgumentError, "#{field_name} is required"
  end
end
