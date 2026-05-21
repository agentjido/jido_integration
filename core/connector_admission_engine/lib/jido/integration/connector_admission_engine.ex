defmodule Jido.Integration.ConnectorAdmissionEngine do
  @moduledoc """
  Memory-default connector admission records.
  """

  alias GroundPlane.PersistencePolicy
  alias Jido.Integration.AgentInterop.Descriptor, as: AgentInteropDescriptor
  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.SkillContracts
  alias Jido.Integration.V2.SkillContracts.SkillPackage

  @store __MODULE__.Store
  @supported_contract_versions ["connector-sdk.v1"]
  @supported_auth_types [:api_token, :oauth2, :app_installation, :native_cli_assertion, :none]
  @admitted_statuses [:admitted, :admitted_skill_package]
  @rejected_statuses [
    :rejected_manifest_collision,
    :rejected_duplicate_capability,
    :rejected_unsafe_scope,
    :rejected_unsupported_auth_profile,
    :rejected_missing_conformance,
    :rejected_contract_mismatch,
    :rejected_tenant_mismatch,
    :rejected_durable_adapter,
    :rejected_external_agent_protocol_not_live,
    :rejected_skill_contract_mismatch
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
  @profile_aliases %{
    "memory-default" => :mickey_mouse,
    "mickey_mouse" => :mickey_mouse,
    "memory_debug" => :memory_debug,
    "local_restart_safe" => :local_restart_safe,
    "integration_postgres" => :integration_postgres,
    "ops_durable" => :ops_durable,
    "full_debug_tracked" => :full_debug_tracked,
    "distributed_partitioned" => :distributed_partitioned
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

  defmodule AgentInteropAdmissionRecord do
    @moduledoc false

    @enforce_keys [
      :admission_ref,
      :interop_ref,
      :tenant_ref,
      :endpoint_ref,
      :policy_ref,
      :capability_count,
      :admission_status,
      :trace_ref,
      :rejection_reason
    ]
    defstruct @enforce_keys
  end

  defmodule SkillPackageAdmissionRecord do
    @moduledoc false

    @enforce_keys [
      :admission_ref,
      :skill_ref,
      :tenant_ref,
      :manifest_hash,
      :policy_refs,
      :credential_posture,
      :runtime_families,
      :entrypoint_count,
      :capability_count,
      :admission_status,
      :trace_ref,
      :release_manifest_ref,
      :rejection_reason
    ]
    defstruct @enforce_keys
  end

  defmodule Store do
    @moduledoc false

    use Agent

    @spec start_link(keyword()) :: Agent.on_start()
    def start_link(opts) do
      name = Keyword.get(opts, :name, __MODULE__)
      Agent.start_link(&initial_state/0, name: name)
    end

    @spec initial_state() :: map()
    def initial_state do
      %{records: %{}, manifest_index: %{}, hash_index: %{}}
    end
  end

  @type admission_status :: atom()
  @type admission_record :: %AdmissionRecord{}
  @type agent_interop_admission_record :: %AgentInteropAdmissionRecord{}
  @type skill_package_admission_record :: %SkillPackageAdmissionRecord{}

  @spec reset!() :: :ok
  def reset! do
    ensure_store!()
    Agent.update(@store, fn _state -> Store.initial_state() end)
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
    persistence_profile = value(attrs, :persistence_profile) || :mickey_mouse
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

  @spec recognize_agent_interop_descriptor(
          AgentInteropDescriptor.t() | map() | keyword(),
          keyword() | map()
        ) ::
          {:error, agent_interop_admission_record()}
  def recognize_agent_interop_descriptor(descriptor_or_attrs, opts \\ []) do
    attrs = normalize_opts(opts)

    case AgentInteropDescriptor.new(descriptor_or_attrs) do
      {:ok, descriptor} ->
        {:error,
         build_agent_interop_record(
           descriptor,
           attrs,
           :rejected_external_agent_protocol_not_live,
           :external_agent_protocol_not_live
         )}

      {:error, %ArgumentError{} = error} ->
        descriptor = fallback_agent_interop_descriptor(descriptor_or_attrs)

        {:error,
         build_agent_interop_record(
           descriptor,
           attrs,
           :rejected_contract_mismatch,
           Exception.message(error)
         )}
    end
  end

  @spec admit_skill_package(SkillPackage.t() | map() | keyword(), keyword() | map()) ::
          {:ok, skill_package_admission_record()} | {:error, skill_package_admission_record()}
  def admit_skill_package(package_or_attrs, opts \\ []) do
    attrs = normalize_opts(opts)

    case SkillContracts.package(package_or_attrs) do
      {:ok, package} ->
        {:ok, build_skill_package_record(package, attrs, :admitted_skill_package, nil)}

      {:error, {:manifest_hash_mismatch, _facts}} ->
        package = fallback_skill_package(package_or_attrs)

        {:error,
         build_skill_package_record(
           package,
           attrs,
           :rejected_skill_contract_mismatch,
           :manifest_hash_mismatch
         )}

      {:error, %ArgumentError{} = error} ->
        package = fallback_skill_package(package_or_attrs)

        {:error,
         build_skill_package_record(
           package,
           attrs,
           :rejected_skill_contract_mismatch,
           Exception.message(error)
         )}

      {:error, reason} ->
        package = fallback_skill_package(package_or_attrs)

        {:error,
         build_skill_package_record(
           package,
           attrs,
           :rejected_skill_contract_mismatch,
           reason
         )}
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

  defp build_agent_interop_record(descriptor, attrs, status, reason) do
    tenant_ref = value(attrs, :tenant_ref) || "tenant://unknown"
    interop_ref = agent_interop_value(descriptor, :interop_ref) || "agent-interop://unknown"

    %AgentInteropAdmissionRecord{
      admission_ref: "agent-interop-admission://#{tenant_ref}/#{interop_ref}",
      interop_ref: interop_ref,
      tenant_ref: tenant_ref,
      endpoint_ref: agent_interop_value(descriptor, :endpoint_ref),
      policy_ref: agent_interop_value(descriptor, :policy_ref),
      capability_count: length(agent_interop_value(descriptor, :capability_refs) || []),
      admission_status: status,
      trace_ref: value(attrs, :trace_ref) || "trace://connector-admission/agent-interop",
      rejection_reason: reason
    }
  end

  defp fallback_agent_interop_descriptor(%AgentInteropDescriptor{} = descriptor), do: descriptor

  defp fallback_agent_interop_descriptor(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = if is_list(attrs), do: Map.new(attrs), else: attrs

    %{
      interop_ref: value(attrs, :interop_ref),
      endpoint_ref: value(attrs, :endpoint_ref),
      policy_ref: value(attrs, :policy_ref),
      capability_refs: value(attrs, :capability_refs) || []
    }
  end

  defp fallback_agent_interop_descriptor(_attrs), do: %{}

  defp agent_interop_value(%AgentInteropDescriptor{} = descriptor, field),
    do: Map.get(descriptor, field)

  defp agent_interop_value(%{} = descriptor, field), do: value(descriptor, field)

  defp build_skill_package_record(package, attrs, status, reason) do
    refs = skill_package_record_refs(package, attrs)

    %SkillPackageAdmissionRecord{
      admission_ref: "skill-admission://#{refs.tenant_ref}/#{refs.skill_ref}",
      skill_ref: refs.skill_ref,
      tenant_ref: refs.tenant_ref,
      manifest_hash: skill_package_value(package, :manifest_hash),
      policy_refs: skill_package_value(package, :policy_refs) || [],
      credential_posture: skill_package_value(package, :credential_posture),
      runtime_families: skill_package_value(package, :allowed_runtime_families) || [],
      entrypoint_count: length(skill_package_value(package, :entrypoints) || []),
      capability_count: length(skill_package_value(package, :capability_refs) || []),
      admission_status: status,
      trace_ref: refs.trace_ref,
      release_manifest_ref: refs.release_manifest_ref,
      rejection_reason: reason
    }
  end

  defp skill_package_record_refs(package, attrs) do
    %{
      tenant_ref:
        first_present([
          value(attrs, :tenant_ref),
          skill_package_value(package, :tenant_ref),
          "tenant://unknown"
        ]),
      skill_ref: skill_package_value(package, :skill_ref) || "skill://unknown",
      trace_ref:
        first_present([
          value(attrs, :trace_ref),
          skill_package_value(package, :trace_ref),
          "trace://connector-admission/skill-package"
        ]),
      release_manifest_ref:
        first_present([
          value(attrs, :release_manifest_ref),
          skill_package_value(package, :release_manifest_ref),
          "release://connector-admission/skill-package"
        ])
    }
  end

  defp first_present(values), do: Enum.find(values, &present_string?/1)

  defp fallback_skill_package(%SkillPackage{} = package), do: package

  defp fallback_skill_package(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = if is_list(attrs), do: Map.new(attrs), else: attrs

    %{
      skill_ref: value(attrs, :skill_ref),
      tenant_ref: value(attrs, :tenant_ref),
      manifest_hash: value(attrs, :manifest_hash),
      policy_refs: value(attrs, :policy_refs) || [],
      credential_posture: value(attrs, :credential_posture),
      allowed_runtime_families: value(attrs, :allowed_runtime_families) || [],
      entrypoints: value(attrs, :entrypoints) || [],
      capability_refs: value(attrs, :capability_refs) || [],
      trace_ref: value(attrs, :trace_ref),
      release_manifest_ref: value(attrs, :release_manifest_ref)
    }
  end

  defp fallback_skill_package(_attrs), do: %{}

  defp skill_package_value(%SkillPackage{} = package, field), do: Map.get(package, field)
  defp skill_package_value(%{} = package, field), do: value(package, field)

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

  defp durable_adapter_missing?(persistence_profile, attrs) do
    case PersistencePolicy.resolve(profile: normalize_profile(persistence_profile)) do
      {:ok, %{durable?: false}} ->
        false

      {:ok, %{id: profile_id, durable?: true}} ->
        registered = list_field(attrs, :registered_durable_adapters)
        not adapter_registered?(registered, persistence_profile, profile_id)

      {:error, _reason} ->
        persistence_profile not in list_field(attrs, :registered_durable_adapters)
    end
  end

  defp adapter_registered?(registered, original_profile, profile_id) do
    profile_name = Atom.to_string(profile_id)

    Enum.any?(registered, fn adapter ->
      adapter in [original_profile, profile_id, profile_name]
    end)
  end

  defp normalize_profile(profile) when is_binary(profile),
    do: Map.get(@profile_aliases, profile, profile)

  defp normalize_profile(profile), do: profile

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
        ensure_application_store_started!()

      _pid ->
        :ok
    end
  end

  defp ensure_application_store_started! do
    case Application.ensure_all_started(:jido_integration_connector_admission_engine) do
      {:ok, _started} ->
        ensure_store_registered!()

      {:error, {:already_started, _app}} ->
        ensure_store_registered!()

      {:error, reason} ->
        raise "failed to start connector admission store supervisor: #{inspect(reason)}"
    end
  end

  defp ensure_store_registered! do
    case Process.whereis(@store) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        raise "connector admission store supervisor started without registering #{@store}"
    end
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
