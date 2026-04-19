defmodule Jido.Integration.V2.LeaseRevocation do
  @moduledoc """
  Phase 4 platform lease revocation and propagation evidence mirror.

  Contract: `Platform.LeaseRevocation.v1`.
  """

  alias Jido.Integration.V2.CanonicalJson
  alias Jido.Integration.V2.Contracts

  @contract_name "Platform.LeaseRevocation.v1"
  @contract_version "1.0.0"
  @lease_statuses [:revoked, :rejected_after_revocation]

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
    :lease_ref,
    :revocation_ref,
    :revoked_at,
    :lease_scope,
    :cache_invalidation_ref,
    :post_revocation_attempt_ref,
    :lease_status
  ]

  @enforce_keys @fields -- [:principal_ref, :system_actor_ref]
  defstruct @fields

  @type lease_status :: :revoked | :rejected_after_revocation
  @type t :: %__MODULE__{}

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec lease_statuses() :: [lease_status()]
  def lease_statuses, do: @lease_statuses

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = revocation), do: normalize(revocation)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = revocation) do
    case normalize(revocation) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = revocation) do
    @fields
    |> Map.new(&{&1, Map.fetch!(revocation, &1)})
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp build!(attrs) do
    attrs = Map.new(attrs)
    principal_ref = optional_string(attrs, :principal_ref)
    system_actor_ref = optional_string(attrs, :system_actor_ref)
    validate_actor_pair!(principal_ref, system_actor_ref)

    %__MODULE__{
      contract_name:
        attrs
        |> Contracts.get(:contract_name, @contract_name)
        |> validate_literal!(@contract_name, :contract_name),
      contract_version:
        attrs
        |> Contracts.get(:contract_version, @contract_version)
        |> validate_literal!(@contract_version, :contract_version),
      tenant_ref: required_string(attrs, :tenant_ref),
      installation_ref: required_string(attrs, :installation_ref),
      workspace_ref: required_string(attrs, :workspace_ref),
      project_ref: required_string(attrs, :project_ref),
      environment_ref: required_string(attrs, :environment_ref),
      principal_ref: principal_ref,
      system_actor_ref: system_actor_ref,
      resource_ref: required_string(attrs, :resource_ref),
      authority_packet_ref: required_string(attrs, :authority_packet_ref),
      permission_decision_ref: required_string(attrs, :permission_decision_ref),
      idempotency_key: required_string(attrs, :idempotency_key),
      trace_id: required_string(attrs, :trace_id),
      correlation_id: required_string(attrs, :correlation_id),
      release_manifest_ref: required_string(attrs, :release_manifest_ref),
      lease_ref: required_string(attrs, :lease_ref),
      revocation_ref: required_string(attrs, :revocation_ref),
      revoked_at: required_datetime(attrs, :revoked_at),
      lease_scope: non_empty_json_object(attrs, :lease_scope),
      cache_invalidation_ref: required_string(attrs, :cache_invalidation_ref),
      post_revocation_attempt_ref: required_string(attrs, :post_revocation_attempt_ref),
      lease_status:
        attrs
        |> Contracts.get(:lease_status, :revoked)
        |> Contracts.validate_enum_atomish!(@lease_statuses, field(:lease_status))
    }
  end

  defp normalize(%__MODULE__{} = revocation) do
    {:ok, revocation |> dump() |> build!()}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_actor_pair!(nil, nil),
    do: raise(ArgumentError, "#{@contract_name} requires principal_ref or system_actor_ref")

  defp validate_actor_pair!(_principal_ref, _system_actor_ref), do: :ok

  defp required_string(attrs, key) do
    attrs
    |> Contracts.fetch_required!(key, field(key))
    |> Contracts.validate_non_empty_string!(field(key))
  end

  defp optional_string(attrs, key) do
    case Contracts.get(attrs, key) do
      nil -> nil
      value -> Contracts.validate_non_empty_string!(value, field(key))
    end
  end

  defp required_datetime(attrs, key) do
    attrs
    |> Contracts.fetch_required!(key, field(key))
    |> datetime!(key)
  end

  defp datetime!(%DateTime{} = value, _key), do: value

  defp datetime!(value, key) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> raise ArgumentError, "#{field(key)} must be ISO-8601"
    end
  end

  defp datetime!(value, key) do
    raise ArgumentError,
          "#{field(key)} must be a DateTime or ISO-8601 string, got: #{inspect(value)}"
  end

  defp non_empty_json_object(attrs, key) do
    value =
      attrs
      |> Contracts.fetch_required!(key, field(key))
      |> CanonicalJson.normalize!()

    cond do
      not is_map(value) ->
        raise ArgumentError, "#{field(key)} must normalize to a JSON object"

      map_size(value) == 0 ->
        raise ArgumentError, "#{field(key)} must be a non-empty JSON object"

      true ->
        value
    end
  end

  defp validate_literal!(value, expected, _key) when value == expected, do: value

  defp validate_literal!(value, expected, key) do
    raise ArgumentError, "#{field(key)} must be #{expected}, got: #{inspect(value)}"
  end

  defp field(key), do: "lease_revocation.#{key}"
end
