defmodule Jido.Integration.ConnectorAdmissionEngine do
  @moduledoc """
  Memory-default connector admission records.
  """

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.Manifest

  @store __MODULE__.Store
  @supported_contract_versions ["connector-sdk.v1"]
  @supported_auth_types [:api_token, :oauth2, :app_installation, :native_cli_assertion, :none]
  @admitted_statuses [:admitted]
  @rejected_statuses [
    :rejected_manifest_collision,
    :rejected_duplicate_capability,
    :rejected_unsafe_scope,
    :rejected_unsupported_auth_profile,
    :rejected_missing_conformance,
    :rejected_contract_mismatch,
    :rejected_tenant_mismatch,
    :rejected_durable_adapter
  ]
  @known_string_keys %{
    "app_config" => :app_config,
    "app_config_ref" => :app_config_ref,
    "conformance" => :conformance,
    "contract_version" => :contract_version,
    "existing_capability_ids" => :existing_capability_ids,
    "manifest_hash" => :manifest_hash,
    "persistence_profile" => :persistence_profile,
    "registered_durable_adapters" => :registered_durable_adapters,
    "release_manifest_ref" => :release_manifest_ref,
    "status" => :status,
    "tenant_ref" => :tenant_ref,
    "trace_ref" => :trace_ref
  }

  defmodule AdmissionRecord do
    @moduledoc false

    @enforce_keys [
      :admission_ref,
      :connector_id,
      :tenant_ref,
      :manifest_hash,
      :contract_version,
      :operation_count,
      :trigger_count,
      :auth_profiles,
      :scopes,
      :duplicate_capabilities,
      :conformance_status,
      :admission_status,
      :persistence_profile,
      :trace_ref,
      :release_manifest_ref
    ]
    defstruct @enforce_keys ++ [:rejection_reason, :app_config_ref]
  end

  @type admission_status :: atom()
  @type admission_record :: %AdmissionRecord{}

  @spec reset!() :: :ok
  def reset! do
    ensure_store!()
    Agent.update(@store, fn _state -> initial_state() end)
  end

  @spec admit(Manifest.t(), keyword() | map()) ::
          {:ok, admission_record()} | {:error, admission_record()}
  def admit(%Manifest{} = manifest, opts \\ []) do
    ensure_store!()

    attrs = normalize_opts(opts)
    manifest_hash = Manifest.canonical_hash(manifest)
    contract_version = Manifest.contract_version(manifest)
    app_config = map_field(attrs, :app_config)
    tenant_ref = value(attrs, :tenant_ref) || value(app_config, :tenant_ref)
    conformance = map_field(attrs, :conformance)
    persistence_profile = value(attrs, :persistence_profile) || "memory-default"
    trace_ref = value(attrs, :trace_ref) || "trace://connector-admission/#{manifest.connector}"

    release_manifest_ref =
      value(attrs, :release_manifest_ref) || "release://connector-admission/phase-e"

    context = %{
      manifest: manifest,
      manifest_hash: manifest_hash,
      contract_version: contract_version,
      tenant_ref: tenant_ref,
      app_config: app_config,
      conformance: conformance,
      persistence_profile: persistence_profile,
      trace_ref: trace_ref,
      release_manifest_ref: release_manifest_ref,
      attrs: attrs
    }

    case admission_rejection(context) do
      nil ->
        record = build_record(context, :admitted, nil)
        Agent.update(@store, &put_record(&1, record))
        {:ok, record}

      reason ->
        record = build_record(context, rejection_status(reason), reason)
        {:error, record}
    end
  end

  @spec records() :: [admission_record()]
  def records do
    ensure_store!()

    @store
    |> Agent.get(& &1.records)
    |> Map.values()
    |> Enum.sort_by(& &1.admission_ref)
  end

  @spec statuses() :: [atom()]
  def statuses, do: @admitted_statuses ++ @rejected_statuses

  defp admission_rejection(context) do
    [
      &tenant_rejection/1,
      &contract_rejection/1,
      &conformance_rejection/1,
      &auth_rejection/1,
      &scope_rejection/1,
      &duplicate_rejection/1,
      &durable_adapter_rejection/1,
      &collision_rejection/1
    ]
    |> Enum.find_value(fn check -> check.(context) end)
  end

  defp tenant_rejection(context) do
    cond do
      not present_string?(context.tenant_ref) -> :tenant_mismatch
      tenant_ref(context.app_config) not in [nil, context.tenant_ref] -> :tenant_mismatch
      true -> nil
    end
  end

  defp contract_rejection(context) do
    if context.contract_version in @supported_contract_versions, do: nil, else: :contract_mismatch
  end

  defp conformance_rejection(context) do
    if conformance_passed?(context.conformance, context.manifest_hash, context.contract_version) do
      nil
    else
      :missing_conformance
    end
  end

  defp auth_rejection(context) do
    if unsupported_auth_profiles(context.manifest.auth) == [] do
      nil
    else
      :unsupported_auth_profile
    end
  end

  defp scope_rejection(context) do
    if Manifest.external_safety_errors(context.manifest) == [], do: nil, else: :unsafe_scope
  end

  defp duplicate_rejection(context) do
    if duplicate_capabilities(context) == [], do: nil, else: :duplicate_capability
  end

  defp durable_adapter_rejection(context) do
    if durable_adapter_missing?(context.persistence_profile, context.attrs) do
      :durable_adapter
    else
      nil
    end
  end

  defp collision_rejection(context) do
    if manifest_collision?(context), do: :manifest_collision, else: nil
  end

  defp build_record(context, status, reason) do
    auth_profiles = auth_profiles(context.manifest.auth)
    scopes = context.manifest.auth.requested_scopes

    %AdmissionRecord{
      admission_ref: "connector-admission://#{context.tenant_ref}/#{context.manifest.connector}",
      connector_id: context.manifest.connector,
      tenant_ref: context.tenant_ref,
      manifest_hash: context.manifest_hash,
      contract_version: context.contract_version,
      operation_count: length(context.manifest.operations),
      trigger_count: length(context.manifest.triggers),
      auth_profiles: auth_profiles,
      scopes: scopes,
      duplicate_capabilities: duplicate_capabilities(context),
      conformance_status: conformance_status(context.conformance),
      admission_status: status,
      persistence_profile: context.persistence_profile,
      trace_ref: context.trace_ref,
      release_manifest_ref: context.release_manifest_ref,
      rejection_reason: reason,
      app_config_ref: value(context.app_config, :app_config_ref)
    }
  end

  defp put_record(state, %AdmissionRecord{} = record) do
    state
    |> Map.update!(:records, &Map.put(&1, record.admission_ref, record))
    |> Map.update!(:manifest_index, &Map.put(&1, record.connector_id, record.manifest_hash))
    |> Map.update!(:hash_index, &Map.put(&1, record.manifest_hash, record.connector_id))
  end

  defp manifest_collision?(context) do
    Agent.get(@store, fn state ->
      connector_collision? =
        case Map.fetch(state.manifest_index, context.manifest.connector) do
          {:ok, existing_hash} -> existing_hash != context.manifest_hash
          :error -> false
        end

      hash_collision? =
        case Map.fetch(state.hash_index, context.manifest_hash) do
          {:ok, existing_connector} -> existing_connector != context.manifest.connector
          :error -> false
        end

      connector_collision? or hash_collision?
    end)
  end

  defp duplicate_capabilities(context) do
    existing =
      context.attrs
      |> list_field(:existing_capability_ids)
      |> MapSet.new()

    context.manifest.capabilities
    |> Enum.map(& &1.id)
    |> Enum.filter(&MapSet.member?(existing, &1))
    |> Enum.sort()
  end

  defp unsupported_auth_profiles(%AuthSpec{} = auth) do
    auth.supported_profiles
    |> Enum.reject(&(Map.get(&1, :auth_type) in @supported_auth_types))
    |> Enum.map(&Map.get(&1, :id))
  end

  defp conformance_passed?(conformance, manifest_hash, contract_version) do
    conformance_status(conformance) == "passed" and
      value(conformance, :manifest_hash) == manifest_hash and
      value(conformance, :contract_version) == contract_version
  end

  defp conformance_status(conformance), do: value(conformance, :status) || "missing"

  defp durable_adapter_missing?("memory-default", _attrs), do: false

  defp durable_adapter_missing?(persistence_profile, attrs) do
    registered = list_field(attrs, :registered_durable_adapters)
    persistence_profile not in registered
  end

  defp rejection_status(:manifest_collision), do: :rejected_manifest_collision
  defp rejection_status(:duplicate_capability), do: :rejected_duplicate_capability
  defp rejection_status(:unsafe_scope), do: :rejected_unsafe_scope
  defp rejection_status(:unsupported_auth_profile), do: :rejected_unsupported_auth_profile
  defp rejection_status(:missing_conformance), do: :rejected_missing_conformance
  defp rejection_status(:contract_mismatch), do: :rejected_contract_mismatch
  defp rejection_status(:tenant_mismatch), do: :rejected_tenant_mismatch
  defp rejection_status(:durable_adapter), do: :rejected_durable_adapter

  defp auth_profiles(%AuthSpec{} = auth) do
    auth.supported_profiles
    |> Enum.map(&Map.get(&1, :id))
    |> Enum.sort()
  end

  defp ensure_store! do
    case Process.whereis(@store) do
      nil ->
        case Agent.start(fn -> initial_state() end, name: @store) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp initial_state do
    %{records: %{}, manifest_index: %{}, hash_index: %{}}
  end

  defp normalize_opts(opts) when is_list(opts), do: opts |> Map.new() |> normalize_opts()

  defp normalize_opts(opts) when is_map(opts) do
    Map.new(opts, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key), do: Map.get(@known_string_keys, key, key)

  defp map_field(attrs, field) do
    case value(attrs, field) do
      %{} = map -> normalize_opts(map)
      _other -> %{}
    end
  end

  defp list_field(attrs, field) do
    case value(attrs, field) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp tenant_ref(app_config), do: value(app_config, :tenant_ref)

  defp value(attrs, field) when is_map(attrs) do
    Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field))
  end

  defp value(_attrs, _field), do: nil

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
end
