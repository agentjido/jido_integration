defmodule Jido.Integration.V2.ServiceSimulationProfile do
  @moduledoc """
  Jido-owned semantic service profile for Phase 6 production simulation.

  The profile binds governed workload/provider intent to installed lower
  scenario refs. Runtime selection happens through owner registries and adapter
  configuration, not caller-supplied mode keywords.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @contract_version "ServiceSimulationProfile.v1"
  @owner_repo "jido_integration"
  @no_egress_prefix "no-egress-policy://"

  @schema Zoi.struct(
            __MODULE__,
            %{
              contract_version:
                Contracts.non_empty_string_schema("service_simulation_profile.contract_version")
                |> Zoi.default(@contract_version),
              profile_id:
                Contracts.non_empty_string_schema("service_simulation_profile.profile_id"),
              version: Contracts.non_empty_string_schema("service_simulation_profile.version"),
              owner_repo:
                Contracts.non_empty_string_schema("service_simulation_profile.owner_repo"),
              environment_scope:
                Contracts.non_empty_string_schema("service_simulation_profile.environment_scope"),
              workload_ref:
                Contracts.non_empty_string_schema("service_simulation_profile.workload_ref"),
              pack_ref: Contracts.non_empty_string_schema("service_simulation_profile.pack_ref"),
              work_class_ref:
                Contracts.non_empty_string_schema("service_simulation_profile.work_class_ref"),
              subject_kind:
                Contracts.non_empty_string_schema("service_simulation_profile.subject_kind"),
              tenant_policy_ref:
                Contracts.non_empty_string_schema("service_simulation_profile.tenant_policy_ref"),
              authority_policy_ref:
                Contracts.non_empty_string_schema(
                  "service_simulation_profile.authority_policy_ref"
                ),
              authorization_scope_requirements: Contracts.any_map_schema(),
              provider_refs:
                Zoi.list(
                  Contracts.non_empty_string_schema("service_simulation_profile.provider_refs")
                ),
              model_refs:
                Zoi.list(
                  Contracts.non_empty_string_schema("service_simulation_profile.model_refs")
                ),
              endpoint_refs:
                Zoi.list(
                  Contracts.non_empty_string_schema("service_simulation_profile.endpoint_refs")
                ),
              budget_profile_ref:
                Contracts.non_empty_string_schema("service_simulation_profile.budget_profile_ref"),
              meter_profile_ref:
                Contracts.non_empty_string_schema("service_simulation_profile.meter_profile_ref"),
              lower_scenario_refs:
                Zoi.list(
                  Contracts.non_empty_string_schema(
                    "service_simulation_profile.lower_scenario_refs"
                  )
                ),
              no_egress_policy_ref:
                Contracts.non_empty_string_schema(
                  "service_simulation_profile.no_egress_policy_ref"
                ),
              evidence_policy_ref:
                Contracts.non_empty_string_schema(
                  "service_simulation_profile.evidence_policy_ref"
                ),
              raw_body_policy: Contracts.any_map_schema(),
              input_fingerprint_policy: Contracts.any_map_schema(),
              cleanup_policy: Contracts.any_map_schema(),
              owner_evidence_refs:
                Zoi.list(
                  Contracts.non_empty_string_schema(
                    "service_simulation_profile.owner_evidence_refs"
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

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = profile), do: normalize(profile)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)

    with :ok <- reject_public_simulation_selector(attrs) do
      __MODULE__
      |> Schema.new(@schema, attrs)
      |> Schema.refine_new(&normalize/1)
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = profile) do
    case normalize(profile) do
      {:ok, profile} -> profile
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, profile} -> profile
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec dump(t()) :: map()
  def dump(%__MODULE__{} = profile) do
    %{
      "contract_version" => profile.contract_version,
      "profile_id" => profile.profile_id,
      "version" => profile.version,
      "owner_repo" => profile.owner_repo,
      "environment_scope" => profile.environment_scope,
      "workload_ref" => profile.workload_ref,
      "pack_ref" => profile.pack_ref,
      "work_class_ref" => profile.work_class_ref,
      "subject_kind" => profile.subject_kind,
      "tenant_policy_ref" => profile.tenant_policy_ref,
      "authority_policy_ref" => profile.authority_policy_ref,
      "authorization_scope_requirements" => profile.authorization_scope_requirements,
      "provider_refs" => profile.provider_refs,
      "model_refs" => profile.model_refs,
      "endpoint_refs" => profile.endpoint_refs,
      "budget_profile_ref" => profile.budget_profile_ref,
      "meter_profile_ref" => profile.meter_profile_ref,
      "lower_scenario_refs" => profile.lower_scenario_refs,
      "no_egress_policy_ref" => profile.no_egress_policy_ref,
      "evidence_policy_ref" => profile.evidence_policy_ref,
      "raw_body_policy" => profile.raw_body_policy,
      "input_fingerprint_policy" => profile.input_fingerprint_policy,
      "cleanup_policy" => profile.cleanup_policy,
      "owner_evidence_refs" => profile.owner_evidence_refs
    }
    |> Contracts.dump_json_safe!()
  end

  defp normalize(%__MODULE__{} = profile) do
    {:ok,
     %__MODULE__{
       profile
       | contract_version: validate_contract_version!(profile.contract_version),
         version: Contracts.validate_semver!(profile.version),
         owner_repo: validate_owner_repo!(profile.owner_repo),
         authorization_scope_requirements:
           normalize_map!(
             profile.authorization_scope_requirements,
             "authorization_scope_requirements"
           ),
         provider_refs: non_empty_string_list!(profile.provider_refs, "provider_refs"),
         model_refs: non_empty_string_list!(profile.model_refs, "model_refs"),
         endpoint_refs: non_empty_string_list!(profile.endpoint_refs, "endpoint_refs"),
         lower_scenario_refs:
           non_empty_string_list!(profile.lower_scenario_refs, "lower_scenario_refs"),
         no_egress_policy_ref: validate_no_egress_policy_ref!(profile.no_egress_policy_ref),
         raw_body_policy: validate_raw_body_policy!(profile.raw_body_policy),
         input_fingerprint_policy:
           validate_input_fingerprint_policy!(profile.input_fingerprint_policy),
         cleanup_policy: normalize_map!(profile.cleanup_policy, "cleanup_policy"),
         owner_evidence_refs:
           non_empty_string_list!(profile.owner_evidence_refs, "owner_evidence_refs")
     }}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp reject_public_simulation_selector(attrs) do
    if Map.has_key?(attrs, :simulation) or Map.has_key?(attrs, "simulation") do
      {:error,
       ArgumentError.exception(
         "public simulation selector is forbidden; install a ServiceSimulationProfile.v1 instead"
       )}
    else
      :ok
    end
  end

  defp validate_contract_version!(version) when version == @contract_version, do: version

  defp validate_contract_version!(version) when is_binary(version) do
    raise ArgumentError,
          "invalid service_simulation_profile.contract_version: #{inspect(version)}; expected #{@contract_version}"
  end

  defp validate_contract_version!(version) do
    raise ArgumentError,
          "service_simulation_profile.contract_version must be a string, got: #{inspect(version)}"
  end

  defp validate_owner_repo!(owner_repo) when owner_repo == @owner_repo, do: owner_repo

  defp validate_owner_repo!(owner_repo) do
    raise ArgumentError,
          "owner_repo must be #{@owner_repo}, got: #{inspect(owner_repo)}"
  end

  defp non_empty_string_list!(values, field_name) when is_list(values) do
    values = Contracts.normalize_string_list!(values, field_name)

    if values == [] do
      raise ArgumentError, "#{field_name} must not be empty"
    end

    values
  end

  defp non_empty_string_list!(values, field_name) do
    raise ArgumentError, "#{field_name} must be a list, got: #{inspect(values)}"
  end

  defp validate_no_egress_policy_ref!(policy_ref) when is_binary(policy_ref) do
    policy_ref = Contracts.validate_non_empty_string!(policy_ref, "no_egress_policy_ref")

    if String.starts_with?(policy_ref, @no_egress_prefix) and
         not contains_forbidden_egress_token?(policy_ref) do
      policy_ref
    else
      raise ArgumentError,
            "no_egress_policy_ref forbids real provider egress, SaaS writes, and fallback selectors"
    end
  end

  defp validate_no_egress_policy_ref!(policy_ref) do
    raise ArgumentError,
          "no_egress_policy_ref must be a string, got: #{inspect(policy_ref)}"
  end

  defp contains_forbidden_egress_token?(policy_ref) do
    normalized = String.downcase(policy_ref)

    Enum.any?(
      ["allow", "real_provider", "real-provider", "real_saas", "real-saas", "fallback"],
      &String.contains?(normalized, &1)
    )
  end

  defp validate_raw_body_policy!(policy) do
    policy = normalize_map!(policy, "raw_body_policy")

    for key <- [
          "durable_persistence",
          "raw_prompts",
          "raw_provider_bodies",
          "full_workflow_histories"
        ] do
      unless Map.get(policy, key) == "deny" do
        raise ArgumentError,
              "raw_body_policy.#{key} must be deny for durable production simulation evidence"
      end
    end

    policy
  end

  defp validate_input_fingerprint_policy!(policy) do
    policy = normalize_map!(policy, "input_fingerprint_policy")

    unless Map.get(policy, "mode") == "transient_hash" do
      raise ArgumentError, "input_fingerprint_policy.mode must be transient_hash"
    end

    unless Map.get(policy, "algorithm") == "sha256" do
      raise ArgumentError, "input_fingerprint_policy.algorithm must be sha256"
    end

    unless Map.get(policy, "persist_raw_body?") == false do
      raise ArgumentError, "input_fingerprint_policy.persist_raw_body? must be false"
    end

    policy
  end

  defp normalize_map!(%{} = value, _field_name), do: Contracts.dump_json_safe!(Map.new(value))

  defp normalize_map!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end
end
