defmodule Jido.Integration.V2.SimulationProfileRegistryEntry do
  @moduledoc """
  Persistent lifecycle entry for installed `ServiceSimulationProfile.v1` records.

  The entry is intentionally audit-first: it stores the active profile version,
  owner and environment scope, lower scenario refs resolved at install time,
  no-egress policy evidence, lifecycle actors, update refs, cleanup state, and
  owner evidence refs. Policy validation is delegated to the service profile and
  lower-binding contracts before an entry can be installed.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema
  alias Jido.Integration.V2.ServiceSimulationProfile
  alias Jido.Integration.V2.ServiceSimulationProfileLowerBinding

  @contract_version "SimulationProfileRegistryEntry.v1"
  @cleanup_statuses [:active, :removed, :cleanup_failed]
  @failure_reason_patterns [
    stale_version: ["stale"],
    missing_owner_evidence: ["owner_evidence_refs"],
    missing_owner: ["owner_refs", "owner ref", "owner cannot"],
    dangling_lower_scenario_ref: ["dangling lower_scenario_ref", "lower_scenario_refs"],
    raw_body_allowed_when_policy_denies: ["raw_body_policy", "input_fingerprint_policy"],
    missing_no_egress_policy: ["no_egress_policy_ref", "no-egress", "missing no-egress"],
    cleanup_failure: ["cleanup"]
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              contract_version:
                Contracts.non_empty_string_schema("simulation_profile_registry.contract_version")
                |> Zoi.default(@contract_version),
              profile_id:
                Contracts.non_empty_string_schema("simulation_profile_registry.profile_id"),
              profile_version:
                Contracts.non_empty_string_schema("simulation_profile_registry.profile_version"),
              owner_refs:
                Zoi.list(
                  Contracts.non_empty_string_schema("simulation_profile_registry.owner_refs")
                ),
              environment_scope:
                Contracts.non_empty_string_schema("simulation_profile_registry.environment_scope"),
              lower_scenario_refs:
                Zoi.list(
                  Contracts.non_empty_string_schema(
                    "simulation_profile_registry.lower_scenario_refs"
                  )
                ),
              no_egress_policy_ref:
                Contracts.non_empty_string_schema(
                  "simulation_profile_registry.no_egress_policy_ref"
                ),
              audit_install_actor_ref:
                Contracts.non_empty_string_schema(
                  "simulation_profile_registry.audit_install_actor_ref"
                ),
              audit_install_timestamp:
                Contracts.datetime_schema("simulation_profile_registry.audit_install_timestamp"),
              audit_update_history_refs:
                Zoi.list(
                  Contracts.non_empty_string_schema(
                    "simulation_profile_registry.audit_update_history_refs"
                  )
                )
                |> Zoi.default([]),
              audit_remove_actor_ref_or_null: Zoi.any(),
              cleanup_status:
                Contracts.enumish_schema(
                  @cleanup_statuses,
                  "simulation_profile_registry.cleanup_status"
                )
                |> Zoi.default(:active),
              cleanup_artifact_refs:
                Zoi.list(
                  Contracts.non_empty_string_schema(
                    "simulation_profile_registry.cleanup_artifact_refs"
                  )
                )
                |> Zoi.default([]),
              owner_evidence_refs:
                Zoi.list(
                  Contracts.non_empty_string_schema(
                    "simulation_profile_registry.owner_evidence_refs"
                  )
                )
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec cleanup_statuses() :: [atom()]
  def cleanup_statuses, do: @cleanup_statuses

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = entry), do: normalize(entry)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs =
      attrs
      |> Map.new()
      |> prepare_attrs()

    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  rescue
    error in ArgumentError -> {:error, error}
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = entry) do
    case normalize(entry) do
      {:ok, entry} -> entry
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, entry} -> entry
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec install(ServiceSimulationProfile.t() | map() | keyword(), [map()], map() | keyword()) ::
          {:ok, t()} | {:error, atom()}
  def install(profile, installed_scenarios, attrs) do
    {:ok, install!(profile, installed_scenarios, attrs)}
  rescue
    error in ArgumentError -> {:error, failure_reason(error)}
  end

  @spec install!(ServiceSimulationProfile.t() | map() | keyword(), [map()], map() | keyword()) ::
          t()
  def install!(profile, installed_scenarios, attrs) do
    attrs = normalize_attrs!(attrs)
    profile = ServiceSimulationProfile.new!(profile)
    binding = ServiceSimulationProfileLowerBinding.bind!(profile, installed_scenarios)

    new!(%{
      profile_id: profile.profile_id,
      profile_version: profile.version,
      owner_refs: fetch_owner_refs!(attrs),
      environment_scope: profile.environment_scope,
      lower_scenario_refs: binding.lower_scenario_refs,
      no_egress_policy_ref: profile.no_egress_policy_ref,
      audit_install_actor_ref: required_string!(attrs, :audit_install_actor_ref),
      audit_install_timestamp: Contracts.get(attrs, :audit_install_timestamp, Contracts.now()),
      audit_update_history_refs:
        string_list!(Contracts.get(attrs, :audit_update_history_refs, [])),
      audit_remove_actor_ref_or_null: nil,
      cleanup_status: :active,
      cleanup_artifact_refs: string_list!(Contracts.get(attrs, :cleanup_artifact_refs, [])),
      owner_evidence_refs: profile.owner_evidence_refs
    })
  end

  @spec update(t(), ServiceSimulationProfile.t() | map() | keyword(), [map()], map() | keyword()) ::
          {:ok, t()} | {:error, atom()}
  def update(%__MODULE__{} = current, profile, installed_scenarios, attrs) do
    {:ok, update!(current, profile, installed_scenarios, attrs)}
  rescue
    error in ArgumentError -> {:error, failure_reason(error)}
  end

  @spec update!(t(), ServiceSimulationProfile.t() | map() | keyword(), [map()], map() | keyword()) ::
          t()
  def update!(%__MODULE__{} = current, profile, installed_scenarios, attrs) do
    attrs = normalize_attrs!(attrs)
    profile = ServiceSimulationProfile.new!(profile)
    binding = ServiceSimulationProfileLowerBinding.bind!(profile, installed_scenarios)

    unless profile.profile_id == current.profile_id do
      raise ArgumentError, "profile_id cannot change during registry update"
    end

    unless Version.compare(profile.version, current.profile_version) == :gt do
      raise ArgumentError, "stale profile version"
    end

    update_ref = required_string!(attrs, :audit_update_history_ref)

    new!(%{
      current
      | profile_version: profile.version,
        environment_scope: profile.environment_scope,
        lower_scenario_refs: binding.lower_scenario_refs,
        no_egress_policy_ref: profile.no_egress_policy_ref,
        audit_update_history_refs: current.audit_update_history_refs ++ [update_ref],
        audit_remove_actor_ref_or_null: nil,
        cleanup_status: :active,
        cleanup_artifact_refs: string_list!(Contracts.get(attrs, :cleanup_artifact_refs, [])),
        owner_evidence_refs: profile.owner_evidence_refs
    })
  end

  @spec remove(t(), map() | keyword()) :: {:ok, t()} | {:error, atom()}
  def remove(%__MODULE__{} = current, attrs) do
    removed = remove!(current, attrs)

    case removed.cleanup_status do
      :cleanup_failed -> {:error, :cleanup_failure}
      :removed -> {:ok, removed}
    end
  rescue
    error in ArgumentError -> {:error, failure_reason(error)}
  end

  @spec remove!(t(), map() | keyword()) :: t()
  def remove!(%__MODULE__{} = current, attrs) do
    attrs = normalize_attrs!(attrs)
    cleanup_status = cleanup_status!(Contracts.get(attrs, :cleanup_status, :removed))

    unless cleanup_status in [:removed, :cleanup_failed] do
      raise ArgumentError, "cleanup_status must be removed or cleanup_failed during remove"
    end

    new!(%{
      current
      | audit_remove_actor_ref_or_null: required_string!(attrs, :audit_remove_actor_ref),
        cleanup_status: cleanup_status,
        cleanup_artifact_refs: string_list!(Contracts.get(attrs, :cleanup_artifact_refs, []))
    })
  end

  @spec select(t(), String.t(), String.t()) :: {:ok, t()} | {:error, atom()}
  def select(%__MODULE__{} = entry, environment_scope, owner_ref) do
    cond do
      entry.cleanup_status != :active ->
        {:error, :stale_version}

      entry.environment_scope != environment_scope ->
        {:error, :environment_mismatch}

      owner_ref not in entry.owner_refs ->
        {:error, :missing_owner}

      missing_no_egress_policy?(entry.no_egress_policy_ref) ->
        {:error, :missing_no_egress_policy}

      true ->
        {:ok, entry}
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = entry) do
    %{
      "contract_version" => entry.contract_version,
      "profile_id" => entry.profile_id,
      "profile_version" => entry.profile_version,
      "owner_refs" => entry.owner_refs,
      "environment_scope" => entry.environment_scope,
      "lower_scenario_refs" => entry.lower_scenario_refs,
      "no_egress_policy_ref" => entry.no_egress_policy_ref,
      "audit_install_actor_ref" => entry.audit_install_actor_ref,
      "audit_install_timestamp" => entry.audit_install_timestamp,
      "audit_update_history_refs" => entry.audit_update_history_refs,
      "audit_remove_actor_ref_or_null" => entry.audit_remove_actor_ref_or_null,
      "cleanup_status" => entry.cleanup_status,
      "cleanup_artifact_refs" => entry.cleanup_artifact_refs,
      "owner_evidence_refs" => entry.owner_evidence_refs
    }
    |> Contracts.dump_json_safe!()
  end

  defp prepare_attrs(attrs) do
    attrs
    |> Map.put_new(:audit_update_history_refs, [])
    |> Map.put_new(
      "audit_update_history_refs",
      Contracts.get(attrs, :audit_update_history_refs, [])
    )
    |> Map.put_new(:audit_remove_actor_ref_or_null, nil)
    |> Map.put_new(
      "audit_remove_actor_ref_or_null",
      Contracts.get(attrs, :audit_remove_actor_ref_or_null)
    )
    |> Map.put_new(:cleanup_status, :active)
    |> Map.put_new("cleanup_status", Contracts.get(attrs, :cleanup_status, :active))
    |> Map.put_new(:cleanup_artifact_refs, [])
    |> Map.put_new("cleanup_artifact_refs", Contracts.get(attrs, :cleanup_artifact_refs, []))
    |> parse_datetime(:audit_install_timestamp)
  end

  defp normalize(%__MODULE__{} = entry) do
    {:ok,
     %__MODULE__{
       entry
       | contract_version: validate_contract_version!(entry.contract_version),
         profile_version:
           Contracts.validate_semver!(
             entry.profile_version,
             "simulation_profile_registry.profile_version"
           ),
         owner_refs: non_empty_string_list!(entry.owner_refs, "owner_refs"),
         lower_scenario_refs: non_empty_lower_scenario_refs!(entry.lower_scenario_refs),
         no_egress_policy_ref: validate_no_egress_policy_ref!(entry.no_egress_policy_ref),
         audit_update_history_refs:
           string_list!(entry.audit_update_history_refs, "audit_update_history_refs"),
         audit_remove_actor_ref_or_null:
           optional_string!(
             entry.audit_remove_actor_ref_or_null,
             "audit_remove_actor_ref_or_null"
           ),
         cleanup_status: cleanup_status!(entry.cleanup_status),
         cleanup_artifact_refs:
           string_list!(entry.cleanup_artifact_refs, "cleanup_artifact_refs"),
         owner_evidence_refs:
           non_empty_string_list!(entry.owner_evidence_refs, "owner_evidence_refs")
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp validate_contract_version!(version) when version == @contract_version, do: version

  defp validate_contract_version!(version) do
    raise ArgumentError,
          "invalid simulation_profile_registry.contract_version: #{inspect(version)}; expected #{@contract_version}"
  end

  defp fetch_owner_refs!(attrs) do
    attrs
    |> Contracts.get(:owner_refs, [])
    |> non_empty_string_list!("owner_refs")
  end

  defp non_empty_lower_scenario_refs!(refs) do
    refs = non_empty_string_list!(refs, "lower_scenario_refs")

    Enum.each(refs, fn ref ->
      unless String.starts_with?(ref, "lower-scenario://") do
        raise ArgumentError, "lower_scenario_refs must contain lower-scenario:// refs"
      end
    end)

    refs
  end

  defp non_empty_string_list!(values, field_name) do
    values = string_list!(values, field_name)

    if values == [] do
      raise ArgumentError, "#{field_name} must not be empty"
    end

    values
  end

  defp string_list!(values, field_name \\ "string_list")

  defp string_list!(values, field_name) when is_list(values),
    do: Contracts.normalize_string_list!(values, field_name)

  defp string_list!(values, field_name) do
    raise ArgumentError, "#{field_name} must be a list, got: #{inspect(values)}"
  end

  defp validate_no_egress_policy_ref!(policy_ref) when is_binary(policy_ref) do
    policy_ref =
      Contracts.validate_non_empty_string!(
        policy_ref,
        "simulation_profile_registry.no_egress_policy_ref"
      )

    if String.starts_with?(policy_ref, "no-egress-policy://") and
         not contains_forbidden_egress_token?(policy_ref) do
      policy_ref
    else
      raise ArgumentError, "missing no-egress policy"
    end
  end

  defp validate_no_egress_policy_ref!(_policy_ref),
    do: raise(ArgumentError, "missing no-egress policy")

  defp contains_forbidden_egress_token?(policy_ref) do
    normalized = String.downcase(policy_ref)

    Enum.any?(
      ["allow", "real_provider", "real-provider", "real_saas", "real-saas", "fallback"],
      &String.contains?(normalized, &1)
    )
  end

  defp missing_no_egress_policy?(policy_ref) do
    is_nil(policy_ref) or policy_ref == "" or contains_forbidden_egress_token?(policy_ref)
  end

  defp optional_string!(nil, _field_name), do: nil

  defp optional_string!(value, field_name) do
    Contracts.validate_non_empty_string!(value, field_name)
  end

  defp cleanup_status!(status) when status in @cleanup_statuses, do: status

  defp cleanup_status!(status) when is_binary(status) do
    case status do
      "active" -> :active
      "removed" -> :removed
      "cleanup_failed" -> :cleanup_failed
      _ -> raise ArgumentError, "invalid cleanup_status: #{inspect(status)}"
    end
  end

  defp cleanup_status!(status),
    do: raise(ArgumentError, "invalid cleanup_status: #{inspect(status)}")

  defp normalize_attrs!(attrs) when is_map(attrs) or is_list(attrs), do: Map.new(attrs)

  defp normalize_attrs!(attrs) do
    raise ArgumentError,
          "registry lifecycle attrs must be a map or keyword list, got: #{inspect(attrs)}"
  end

  defp required_string!(attrs, key) do
    attrs
    |> Contracts.fetch_required!(key, Atom.to_string(key))
    |> Contracts.validate_non_empty_string!(Atom.to_string(key))
  end

  defp parse_datetime(attrs, key) do
    value = Contracts.get(attrs, key)

    if is_binary(value) do
      case DateTime.from_iso8601(value) do
        {:ok, datetime, _offset} ->
          attrs
          |> Map.put(key, datetime)
          |> Map.put(Atom.to_string(key), datetime)

        {:error, _reason} ->
          raise ArgumentError, "#{key} must be ISO-8601"
      end
    else
      attrs
    end
  end

  defp failure_reason(%ArgumentError{message: message}) do
    normalized = String.downcase(message)

    Enum.find_value(@failure_reason_patterns, :invalid_registry_entry, fn {reason, patterns} ->
      if Enum.any?(patterns, &String.contains?(normalized, &1)), do: reason
    end)
  end
end
