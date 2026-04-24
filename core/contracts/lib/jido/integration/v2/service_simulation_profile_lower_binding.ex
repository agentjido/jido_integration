defmodule Jido.Integration.V2.ServiceSimulationProfileLowerBinding do
  @moduledoc """
  Install-time binding from `ServiceSimulationProfile.v1` to lower scenarios.

  This module validates lower owner declarations supplied by the profile
  installer. It intentionally does not import lower owner repos or defer missing
  refs to runtime, because dangling lower refs must fail before a profile is
  made installable.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ServiceSimulationProfile

  @scenario_contract_version "ExecutionPlane.LowerSimulationScenario.v1"
  @evidence_contract_version "ExecutionPlane.LowerSimulationEvidence.v1"
  @lower_owner_repos [
    "execution_plane",
    "cli_subprocess_core",
    "pristine",
    "prismatic",
    "self_hosted_inference_core"
  ]
  @protocol_surfaces ["process", "http", "graphql", "self_hosted"]
  @matcher_classes ["deterministic_over_input", "artifact_ref", "frozen_fixture"]
  @forbidden_semantic_keys ~w[
    budget_profile_ref
    cost_policy
    meter_profile_ref
    model_refs
    provider_refs
    semantic_policy
  ]
  @scenario_shape_field "status_or_exit_or_response_or_stream_or_chunk_or_fault_shape"

  defstruct [
    :profile_contract_version,
    :profile_id,
    :profile_version,
    :profile_owner_repo,
    :environment_scope,
    :resolution_phase,
    :lower_scenario_refs,
    :resolved_lower_scenarios,
    :owner_repos,
    :protocol_surfaces
  ]

  @type t :: %__MODULE__{
          profile_contract_version: String.t(),
          profile_id: String.t(),
          profile_version: String.t(),
          profile_owner_repo: String.t(),
          environment_scope: String.t(),
          resolution_phase: :profile_install,
          lower_scenario_refs: [String.t()],
          resolved_lower_scenarios: [map()],
          owner_repos: [String.t()],
          protocol_surfaces: [String.t()]
        }

  @spec bind(
          ServiceSimulationProfile.t() | map() | keyword(),
          [map() | keyword()],
          keyword() | map()
        ) ::
          {:ok, t()} | {:error, Exception.t()}
  def bind(profile, installed_scenarios, opts \\ []) do
    {:ok, build!(profile, installed_scenarios, opts)}
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec bind!(
          ServiceSimulationProfile.t() | map() | keyword(),
          [map() | keyword()],
          keyword() | map()
        ) ::
          t()
  def bind!(profile, installed_scenarios, opts \\ []) do
    case bind(profile, installed_scenarios, opts) do
      {:ok, binding} -> binding
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = binding) do
    %{
      "profile_contract_version" => binding.profile_contract_version,
      "profile_id" => binding.profile_id,
      "profile_version" => binding.profile_version,
      "profile_owner_repo" => binding.profile_owner_repo,
      "environment_scope" => binding.environment_scope,
      "resolution_phase" => binding.resolution_phase,
      "lower_scenario_refs" => binding.lower_scenario_refs,
      "resolved_lower_scenarios" => binding.resolved_lower_scenarios,
      "owner_repos" => binding.owner_repos,
      "protocol_surfaces" => binding.protocol_surfaces
    }
    |> Contracts.dump_json_safe!()
  end

  defp build!(profile, installed_scenarios, opts) do
    opts = normalize_opts!(opts)
    reject_public_simulation_selector!(opts)
    reject_runtime_resolution!(opts)

    profile = normalize_profile!(profile)
    installed_scenarios = normalize_installed_scenarios!(installed_scenarios)
    scenario_index = index_scenarios!(installed_scenarios)

    resolved_lower_scenarios =
      Enum.map(profile.lower_scenario_refs, &fetch_installed_scenario!(&1, scenario_index))

    %__MODULE__{
      profile_contract_version: profile.contract_version,
      profile_id: profile.profile_id,
      profile_version: profile.version,
      profile_owner_repo: profile.owner_repo,
      environment_scope: profile.environment_scope,
      resolution_phase: :profile_install,
      lower_scenario_refs: profile.lower_scenario_refs,
      resolved_lower_scenarios: resolved_lower_scenarios,
      owner_repos:
        resolved_lower_scenarios |> Enum.map(&Map.fetch!(&1, "owner_repo")) |> unique(),
      protocol_surfaces:
        resolved_lower_scenarios |> Enum.map(&Map.fetch!(&1, "protocol_surface")) |> unique()
    }
  end

  defp normalize_profile!(%ServiceSimulationProfile{} = profile) do
    ServiceSimulationProfile.new!(profile)
  end

  defp normalize_profile!(profile) when is_map(profile) or is_list(profile) do
    ServiceSimulationProfile.new!(profile)
  end

  defp normalize_profile!(profile) do
    raise ArgumentError,
          "profile must be a ServiceSimulationProfile.v1 map, got: #{inspect(profile)}"
  end

  defp normalize_installed_scenarios!(installed_scenarios) when is_list(installed_scenarios) do
    if Keyword.keyword?(installed_scenarios) do
      raise ArgumentError, "installed lower scenario declarations must be a list of maps"
    end

    Enum.map(installed_scenarios, &normalize_scenario!/1)
  end

  defp normalize_installed_scenarios!(installed_scenarios) do
    raise ArgumentError,
          "installed lower scenario declarations must be a list, got: #{inspect(installed_scenarios)}"
  end

  defp normalize_scenario!(scenario) do
    scenario
    |> normalize_attrs!("lower scenario declaration")
    |> Contracts.dump_json_safe!()
    |> reject_semantic_provider_policy!()
    |> validate_scenario_contract!()
  end

  defp validate_scenario_contract!(attrs) do
    contract_version =
      attrs
      |> fetch_required_string!("contract_version")
      |> validate_literal!(
        @scenario_contract_version,
        "lower_scenario.contract_version"
      )

    scenario_id =
      attrs
      |> fetch_required_string!("scenario_id")
      |> validate_lower_scenario_ref!()

    version =
      attrs
      |> fetch_required_string!("version")
      |> Contracts.validate_semver!("lower_scenario.version")

    owner_repo =
      attrs
      |> fetch_required_string!("owner_repo")
      |> validate_owner_repo!()

    protocol_surface =
      attrs
      |> fetch_required_string!("protocol_surface")
      |> validate_supported!("protocol_surface", @protocol_surfaces)

    matcher_class =
      attrs
      |> fetch_required_string!("matcher_class")
      |> validate_supported!("matcher_class", @matcher_classes)

    %{
      "contract_version" => contract_version,
      "scenario_id" => scenario_id,
      "version" => version,
      "owner_repo" => owner_repo,
      "route_kind" => fetch_required_string!(attrs, "route_kind"),
      "protocol_surface" => protocol_surface,
      "matcher_class" => matcher_class,
      @scenario_shape_field => fetch_required_map!(attrs, @scenario_shape_field),
      "no_egress_assertion" => validate_no_egress_assertion!(attrs),
      "bounded_evidence_projection" => validate_bounded_evidence_projection!(attrs),
      "input_fingerprint_ref" => fetch_required_string!(attrs, "input_fingerprint_ref"),
      "cleanup_behavior" => fetch_required_map!(attrs, "cleanup_behavior")
    }
  end

  defp index_scenarios!(scenarios) do
    Enum.reduce(scenarios, %{}, fn scenario, acc ->
      scenario_id = Map.fetch!(scenario, "scenario_id")

      if Map.has_key?(acc, scenario_id) do
        raise ArgumentError, "duplicate lower_scenario_ref declaration: #{scenario_id}"
      end

      Map.put(acc, scenario_id, scenario)
    end)
  end

  defp fetch_installed_scenario!(scenario_ref, scenario_index) do
    case Map.fetch(scenario_index, scenario_ref) do
      {:ok, scenario} ->
        scenario

      :error ->
        raise ArgumentError,
              "dangling lower_scenario_ref #{inspect(scenario_ref)} has no installed owner declaration"
    end
  end

  defp normalize_opts!(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      Map.new(opts)
    else
      raise ArgumentError, "binding options must be a keyword list or map"
    end
  end

  defp normalize_opts!(%{} = opts), do: Map.new(opts)

  defp normalize_opts!(opts) do
    raise ArgumentError, "binding options must be a keyword list or map, got: #{inspect(opts)}"
  end

  defp reject_public_simulation_selector!(opts) do
    if has_key?(opts, "simulation") do
      raise ArgumentError,
            "public simulation selector is forbidden; install a ServiceSimulationProfile.v1 binding instead"
    end

    :ok
  end

  defp reject_runtime_resolution!(opts) do
    opts
    |> optional_value("resolution_phase", :profile_install)
    |> validate_resolution_phase!("resolution_phase")

    opts
    |> optional_value("resolve_at", :profile_install)
    |> validate_resolution_phase!("resolve_at")
  end

  defp validate_resolution_phase!(phase, _field)
       when phase in [:profile_install, "profile_install", nil],
       do: :ok

  defp validate_resolution_phase!(phase, _field) when phase in [:runtime, "runtime"] do
    raise ArgumentError,
          "runtime lower scenario resolution is forbidden; resolve lower_scenario_refs at profile install"
  end

  defp validate_resolution_phase!(phase, field) do
    raise ArgumentError, "#{field} must be profile_install, got: #{inspect(phase)}"
  end

  defp reject_semantic_provider_policy!(attrs) do
    if Enum.any?(@forbidden_semantic_keys, &Map.has_key?(attrs, &1)) do
      raise ArgumentError,
            "semantic provider policy must not be owned by lower scenario declarations"
    end

    attrs
  end

  defp validate_no_egress_assertion!(attrs) do
    assertion = fetch_required_map!(attrs, "no_egress_assertion")

    unless Map.get(assertion, "external_egress") == "deny" do
      raise ArgumentError, "no_egress_assertion.external_egress must be deny"
    end

    unless Map.get(assertion, "process_spawn") == "deny" do
      raise ArgumentError, "no_egress_assertion.process_spawn must be deny"
    end

    assertion
  end

  defp validate_bounded_evidence_projection!(attrs) do
    projection = fetch_required_map!(attrs, "bounded_evidence_projection")

    if Map.get(projection, "target_contract") == "ExecutionOutcome.v1.raw_payload" do
      raise ArgumentError, "ExecutionOutcome.v1.raw_payload must not be narrowed in place"
    end

    unless Map.get(projection, "contract_version") == @evidence_contract_version do
      raise ArgumentError,
            "bounded_evidence_projection.contract_version must be #{@evidence_contract_version}"
    end

    unless Map.get(projection, "raw_payload_persistence") == "shape_only" do
      raise ArgumentError,
            "bounded_evidence_projection.raw_payload_persistence must be shape_only"
    end

    projection
  end

  defp fetch_required_string!(attrs, key) do
    attrs
    |> fetch_required!(key)
    |> Contracts.validate_non_empty_string!(key)
  end

  defp fetch_required_map!(attrs, key) do
    value = fetch_required!(attrs, key)

    if is_map(value) do
      Contracts.dump_json_safe!(value)
    else
      raise ArgumentError, "#{key} must be a map, got: #{inspect(value)}"
    end
  end

  defp fetch_required!(attrs, key) when is_binary(key) do
    case Map.fetch(attrs, key) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "#{key} is required"
    end
  end

  defp validate_literal!(value, value, _field), do: value

  defp validate_literal!(value, expected, field) do
    raise ArgumentError, "#{field} must be #{expected}, got: #{inspect(value)}"
  end

  defp validate_lower_scenario_ref!(scenario_id) do
    if String.starts_with?(scenario_id, "lower-scenario://") do
      scenario_id
    else
      raise ArgumentError,
            "lower_scenario.scenario_id must be a lower-scenario:// ref, got: #{inspect(scenario_id)}"
    end
  end

  defp validate_owner_repo!(owner_repo) do
    if owner_repo in @lower_owner_repos do
      owner_repo
    else
      raise ArgumentError,
            "owner_repo must be a Phase 6 lower scenario owner repo, got: #{inspect(owner_repo)}"
    end
  end

  defp validate_supported!(value, field, supported) do
    if value in supported do
      value
    else
      raise ArgumentError, "#{field} unsupported value: #{inspect(value)}"
    end
  end

  defp normalize_attrs!(%_{} = attrs, _field), do: Map.from_struct(attrs)
  defp normalize_attrs!(%{} = attrs, _field), do: Map.new(attrs)

  defp normalize_attrs!(attrs, field) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      Map.new(attrs)
    else
      raise ArgumentError, "#{field} must be a map or keyword list"
    end
  end

  defp normalize_attrs!(attrs, field) do
    raise ArgumentError, "#{field} must be a map or keyword list, got: #{inspect(attrs)}"
  end

  defp has_key?(map, key) when is_binary(key) do
    Map.has_key?(map, key) or Map.has_key?(map, known_atom_key!(key))
  end

  defp optional_value(map, key, default) when is_binary(key) do
    Map.get(map, key, Map.get(map, known_atom_key!(key), default))
  end

  defp known_atom_key!("resolve_at"), do: :resolve_at
  defp known_atom_key!("resolution_phase"), do: :resolution_phase
  defp known_atom_key!("simulation"), do: :simulation

  defp known_atom_key!(key) do
    raise ArgumentError, "unknown binding option key: #{inspect(key)}"
  end

  defp unique(values) do
    Enum.reduce(values, [], fn value, acc ->
      if value in acc, do: acc, else: acc ++ [value]
    end)
  end
end
