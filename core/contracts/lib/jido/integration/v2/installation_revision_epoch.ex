defmodule Jido.Integration.V2.InstallationRevisionEpoch do
  @moduledoc """
  Phase 4 platform revision and activation-epoch fence evidence mirror.

  Contract: `Platform.InstallationRevisionEpoch.v1`.
  """

  alias Jido.Integration.V2.Contracts

  @contract_name "Platform.InstallationRevisionEpoch.v1"
  @contract_version "1.0.0"
  @fence_statuses [:accepted, :rejected]

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
    :installation_revision,
    :activation_epoch,
    :lease_epoch,
    :node_id,
    :fence_decision_ref,
    :fence_status,
    :stale_reason,
    :attempted_installation_revision,
    :attempted_activation_epoch,
    :attempted_lease_epoch,
    :mixed_revision_node_ref,
    :rollout_window_ref
  ]

  @enforce_keys @fields --
                  [
                    :principal_ref,
                    :system_actor_ref,
                    :attempted_installation_revision,
                    :attempted_activation_epoch,
                    :attempted_lease_epoch,
                    :mixed_revision_node_ref,
                    :rollout_window_ref
                  ]
  defstruct @fields

  @type fence_status :: :accepted | :rejected
  @type t :: %__MODULE__{}

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec fence_statuses() :: [fence_status()]
  def fence_statuses, do: @fence_statuses

  @spec new(t() | map() | keyword()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = fence), do: normalize(fence)

  def new(attrs) do
    {:ok, build!(attrs)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = fence) do
    case normalize(fence) do
      {:ok, normalized} -> normalized
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs), do: build!(attrs)

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = fence) do
    @fields
    |> Map.new(&{&1, Map.fetch!(fence, &1)})
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp build!(attrs) do
    attrs = Map.new(attrs)
    principal_ref = optional_string(attrs, :principal_ref)
    system_actor_ref = optional_string(attrs, :system_actor_ref)
    validate_actor_pair!(principal_ref, system_actor_ref)

    fence = %__MODULE__{
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
      installation_revision: required_non_neg_integer(attrs, :installation_revision),
      activation_epoch: required_non_neg_integer(attrs, :activation_epoch),
      lease_epoch: required_non_neg_integer(attrs, :lease_epoch),
      node_id: required_string(attrs, :node_id),
      fence_decision_ref: required_string(attrs, :fence_decision_ref),
      fence_status:
        attrs
        |> Contracts.fetch_required!(:fence_status, field(:fence_status))
        |> Contracts.validate_enum_atomish!(@fence_statuses, field(:fence_status)),
      stale_reason: required_string(attrs, :stale_reason),
      attempted_installation_revision:
        optional_non_neg_integer(attrs, :attempted_installation_revision),
      attempted_activation_epoch: optional_non_neg_integer(attrs, :attempted_activation_epoch),
      attempted_lease_epoch: optional_non_neg_integer(attrs, :attempted_lease_epoch),
      mixed_revision_node_ref: optional_string(attrs, :mixed_revision_node_ref),
      rollout_window_ref: optional_string(attrs, :rollout_window_ref)
    }

    validate_fence_semantics!(fence)
  end

  defp normalize(%__MODULE__{} = fence) do
    {:ok, fence |> dump() |> build!()}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_actor_pair!(nil, nil),
    do: raise(ArgumentError, "#{@contract_name} requires principal_ref or system_actor_ref")

  defp validate_actor_pair!(_principal_ref, _system_actor_ref), do: :ok

  defp validate_fence_semantics!(%__MODULE__{fence_status: :accepted} = fence) do
    if fence.stale_reason != "none" do
      raise ArgumentError, "#{@contract_name} accepted fences must use stale_reason none"
    end

    if attempted_drift?(fence) do
      raise ArgumentError, "#{@contract_name} accepted fences cannot carry stale attempted values"
    end

    fence
  end

  defp validate_fence_semantics!(%__MODULE__{fence_status: :rejected} = fence) do
    if fence.stale_reason == "none" or not stale_attempt?(fence) do
      raise ArgumentError, "#{@contract_name} rejected fences require stale attempted evidence"
    end

    fence
  end

  defp attempted_drift?(fence) do
    Enum.any?(
      [
        {fence.attempted_installation_revision, fence.installation_revision},
        {fence.attempted_activation_epoch, fence.activation_epoch},
        {fence.attempted_lease_epoch, fence.lease_epoch}
      ],
      fn
        {nil, _current} -> false
        {attempted, current} -> attempted != current
      end
    )
  end

  defp stale_attempt?(fence) do
    Enum.any?(
      [
        {fence.attempted_installation_revision, fence.installation_revision},
        {fence.attempted_activation_epoch, fence.activation_epoch},
        {fence.attempted_lease_epoch, fence.lease_epoch}
      ],
      fn
        {nil, _current} -> false
        {attempted, current} -> attempted < current
      end
    )
  end

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

  defp required_non_neg_integer(attrs, key) do
    attrs
    |> Contracts.fetch_required!(key, field(key))
    |> non_neg_integer!(key)
  end

  defp optional_non_neg_integer(attrs, key) do
    case Contracts.get(attrs, key) do
      nil -> nil
      value -> non_neg_integer!(value, key)
    end
  end

  defp non_neg_integer!(value, _key) when is_integer(value) and value >= 0, do: value

  defp non_neg_integer!(value, key) do
    raise ArgumentError, "#{field(key)} must be a non-negative integer, got: #{inspect(value)}"
  end

  defp validate_literal!(value, expected, _key) when value == expected, do: value

  defp validate_literal!(value, expected, key) do
    raise ArgumentError, "#{field(key)} must be #{expected}, got: #{inspect(value)}"
  end

  defp field(key), do: "installation_revision_epoch.#{key}"
end
