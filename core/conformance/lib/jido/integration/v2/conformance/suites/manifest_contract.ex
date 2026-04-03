defmodule Jido.Integration.V2.Conformance.Suites.ManifestContract do
  @moduledoc false

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Conformance.SuiteResult
  alias Jido.Integration.V2.Conformance.SuiteSupport

  @spec run(map()) :: SuiteResult.t()
  def run(%{manifest: manifest}) do
    manifest_map = Map.from_struct(manifest)
    connector = Map.get(manifest_map, :connector)
    operations = Map.get(manifest_map, :operations, [])
    triggers = Map.get(manifest_map, :triggers, [])
    capabilities = Map.get(manifest_map, :capabilities, [])
    capability_ids = Enum.map(capabilities, &Map.get(&1, :id))
    operation_ids = Enum.map(operations, &Map.get(&1, :operation_id))
    trigger_ids = Enum.map(triggers, &Map.get(&1, :trigger_id))
    derived_runtime_families = derive_runtime_families(operations, triggers)
    runtime_families = Map.get(manifest_map, :runtime_families, [])
    auth = Map.get(manifest_map, :auth)
    missing_scopes = missing_requested_scopes(auth, operations, triggers)
    missing_trigger_secrets = missing_trigger_secrets(auth, triggers)

    checks =
      [
        SuiteSupport.check(
          "manifest.connector.present",
          is_binary(connector) and String.trim(connector) != "",
          "manifest.connector must be a non-empty string"
        ),
        SuiteSupport.check(
          "manifest.auth.present",
          match?(%AuthSpec{}, Map.get(manifest_map, :auth)),
          "manifest.auth must be an AuthSpec"
        )
      ] ++
        auth_contract_checks(auth) ++
        [
          SuiteSupport.check(
            "manifest.catalog.present",
            match?(%CatalogSpec{}, Map.get(manifest_map, :catalog)),
            "manifest.catalog must be a CatalogSpec"
          ),
          SuiteSupport.check(
            "manifest.authored_entries.present",
            operation_ids != [] or trigger_ids != [],
            "connector manifests must declare at least one authored operation or trigger"
          ),
          SuiteSupport.check(
            "manifest.auth.requested_scopes.cover_required",
            missing_scopes == [],
            "manifest.auth.requested_scopes must cover all authored operation and trigger required_scopes"
          ),
          SuiteSupport.check(
            "manifest.auth.secret_names.cover_trigger_secrets",
            missing_trigger_secrets == [],
            "manifest.auth.secret_names must declare every authored trigger verification secret_name and secret_requirements entry"
          ),
          SuiteSupport.check(
            "manifest.operations.deterministic",
            operation_ids == Enum.sort(operation_ids),
            "manifest operations must be emitted in deterministic id order"
          ),
          SuiteSupport.check(
            "manifest.triggers.deterministic",
            trigger_ids == Enum.sort(trigger_ids),
            "manifest triggers must be emitted in deterministic id order"
          ),
          SuiteSupport.check(
            "manifest.runtime_families.match_specs",
            runtime_families == derived_runtime_families,
            "manifest runtime_families must match the authored operation and trigger specs"
          ),
          SuiteSupport.check(
            "manifest.capability_order.deterministic",
            capability_ids == Enum.sort(capability_ids),
            "manifest capabilities must be emitted in deterministic id order"
          ),
          SuiteSupport.check(
            "manifest.metadata.map",
            is_map(Map.get(manifest_map, :metadata)),
            "manifest.metadata must be a map"
          )
        ]

    SuiteResult.from_checks(
      :manifest_contract,
      checks,
      "Manifest and connector identity stay deterministic"
    )
  end

  defp derive_runtime_families(operations, triggers) do
    (Enum.map(operations, &Map.get(&1, :runtime_class)) ++
       Enum.map(triggers, &Map.get(&1, :runtime_class)))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp missing_requested_scopes(%AuthSpec{} = auth, operations, triggers) do
    (Enum.flat_map(operations, &required_scopes(Map.get(&1, :permissions, %{}))) ++
       Enum.flat_map(triggers, &required_scopes(Map.get(&1, :permissions, %{}))))
    |> Enum.uniq()
    |> Enum.sort()
    |> Kernel.--(Enum.uniq(auth.requested_scopes))
  end

  defp missing_requested_scopes(_auth, _operations, _triggers), do: [:invalid_auth]

  defp missing_trigger_secrets(%AuthSpec{} = auth, triggers) do
    triggers
    |> Enum.flat_map(&trigger_secret_names/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Kernel.--(Enum.uniq(auth.secret_names))
  end

  defp missing_trigger_secrets(_auth, _triggers), do: [:invalid_auth]

  defp auth_contract_checks(%AuthSpec{} = auth) do
    profiles = Map.get(auth, :supported_profiles, [])

    context = %{
      auth: auth,
      profiles: profiles,
      profile_ids: Enum.map(profiles, &Map.get(&1, :id)),
      install: normalize_map(Map.get(auth, :install, %{})),
      reauth: normalize_map(Map.get(auth, :reauth, %{})),
      install_required_profile_ids: profile_ids(profiles, :install_required),
      reauth_supported_profile_ids: profile_ids(profiles, :reauth_supported),
      default_profile: default_profile(auth)
    }

    auth_identity_checks(context) ++
      auth_union_checks(context) ++
      install_auth_checks(context) ++
      reauth_auth_checks(context) ++
      Enum.flat_map(profiles, &profile_checks/1)
  end

  defp auth_contract_checks(_auth), do: []

  defp auth_identity_checks(context) do
    auth = context.auth
    profile_ids = context.profile_ids

    [
      SuiteSupport.check(
        "manifest.auth.supported_profiles.present",
        is_list(context.profiles) and context.profiles != [],
        "manifest.auth must declare at least one supported_profile"
      ),
      SuiteSupport.check(
        "manifest.auth.supported_profiles.unique_ids",
        profile_ids == Enum.uniq(profile_ids),
        "manifest.auth.supported_profiles must use unique profile ids"
      ),
      SuiteSupport.check(
        "manifest.auth.default_profile.declared",
        auth.default_profile in profile_ids,
        "manifest.auth.default_profile must refer to a declared supported_profile"
      ),
      SuiteSupport.check(
        "manifest.auth.auth_type.matches_default_profile",
        auth.auth_type == Map.get(context.default_profile, :auth_type),
        "manifest.auth.auth_type must match the authored default supported_profile auth_type"
      )
    ]
  end

  defp auth_union_checks(context) do
    auth = context.auth
    profiles = context.profiles

    [
      SuiteSupport.check(
        "manifest.auth.management_modes.cover_profiles",
        normalize_atom_list(auth.management_modes) ==
          union_profile_atom_values(profiles, :management_modes),
        "manifest.auth.management_modes must match the union of profile management_modes"
      ),
      SuiteSupport.check(
        "manifest.auth.requested_scopes.cover_profiles",
        normalize_string_list(auth.requested_scopes) ==
          union_profile_string_values(profiles, :required_scopes),
        "manifest.auth.requested_scopes must match the union of profile required_scopes"
      ),
      SuiteSupport.check(
        "manifest.auth.durable_secret_fields.cover_profiles",
        normalize_string_list(auth.durable_secret_fields) ==
          union_profile_string_values(profiles, :durable_secret_fields),
        "manifest.auth.durable_secret_fields must match the union of profile durable_secret_fields"
      ),
      SuiteSupport.check(
        "manifest.auth.lease_fields.cover_profiles",
        normalize_string_list(auth.lease_fields) ==
          union_profile_string_values(profiles, :lease_fields),
        "manifest.auth.lease_fields must match the union of profile lease_fields"
      )
    ]
  end

  defp install_auth_checks(context) do
    install = context.install
    profiles = context.profiles

    [
      SuiteSupport.check(
        "manifest.auth.install.profiles.declared",
        declared_profile_ids?(install, context.profile_ids),
        "manifest.auth.install.profiles must refer to declared supported_profiles"
      ),
      SuiteSupport.check(
        "manifest.auth.install.profiles.match_install_required",
        install_profile_ids(install) == context.install_required_profile_ids,
        "manifest.auth.install.profiles must match the declared install_required profile ids"
      ),
      SuiteSupport.check(
        "manifest.auth.install.required.when_profiles_present",
        install_profile_ids(install) == [] or SuiteSupport.fetch(install, :required, false),
        "manifest.auth.install.required must be true when install.profiles are declared"
      ),
      SuiteSupport.check(
        "manifest.auth.install.required.when_install_profiles_exist",
        context.install_required_profile_ids == [] or
          SuiteSupport.fetch(install, :required, false),
        "manifest.auth.install.required must be true when any profile requires install"
      ),
      SuiteSupport.check(
        "manifest.auth.install.hosted_callback_matches_profiles",
        not SuiteSupport.fetch(install, :hosted_callback_supported, false) or
          any_profile?(profiles, install_profile_ids(install), :callback_required),
        "manifest.auth.install.hosted_callback_supported requires a callback-capable install profile"
      ),
      SuiteSupport.check(
        "manifest.auth.install.state_required.when_callback_profiles_exist",
        not any_profile?(profiles, install_profile_ids(install), :callback_required) or
          SuiteSupport.fetch(install, :state_required, false),
        "manifest.auth.install.state_required must be true when install callback profiles are declared"
      ),
      SuiteSupport.check(
        "manifest.auth.install.pkce_supported.when_pkce_profiles_exist",
        not any_profile?(profiles, install_profile_ids(install), :pkce_required) or
          SuiteSupport.fetch(install, :pkce_supported, false),
        "manifest.auth.install.pkce_supported must be true when install PKCE profiles are declared"
      ),
      SuiteSupport.check(
        "manifest.auth.install.callback_route_kind.when_hosted",
        is_nil(SuiteSupport.fetch(install, :callback_route_kind)) or
          SuiteSupport.fetch(install, :hosted_callback_supported, false),
        "manifest.auth.install.callback_route_kind may only be declared when hosted_callback_supported is true"
      )
    ]
  end

  defp reauth_auth_checks(context) do
    reauth = context.reauth
    profiles = context.profiles

    [
      SuiteSupport.check(
        "manifest.auth.reauth.profiles.declared",
        declared_profile_ids?(reauth, context.profile_ids),
        "manifest.auth.reauth.profiles must refer to declared supported_profiles"
      ),
      SuiteSupport.check(
        "manifest.auth.reauth.profiles.match_reauth_supported",
        reauth_profile_ids(reauth) == context.reauth_supported_profile_ids,
        "manifest.auth.reauth.profiles must match the declared reauth_supported profile ids"
      ),
      SuiteSupport.check(
        "manifest.auth.reauth.supported.when_profiles_present",
        reauth_profile_ids(reauth) == [] or SuiteSupport.fetch(reauth, :supported, false),
        "manifest.auth.reauth.supported must be true when reauth.profiles are declared"
      ),
      SuiteSupport.check(
        "manifest.auth.reauth.supported.when_reauth_profiles_exist",
        context.reauth_supported_profile_ids == [] or
          SuiteSupport.fetch(reauth, :supported, false),
        "manifest.auth.reauth.supported must be true when any profile supports reauth"
      ),
      SuiteSupport.check(
        "manifest.auth.reauth.hosted_callback_matches_profiles",
        not SuiteSupport.fetch(reauth, :hosted_callback_supported, false) or
          any_profile?(profiles, reauth_profile_ids(reauth), :callback_required),
        "manifest.auth.reauth.hosted_callback_supported requires a callback-capable reauth profile"
      ),
      SuiteSupport.check(
        "manifest.auth.reauth.state_required.when_callback_profiles_exist",
        not any_profile?(profiles, reauth_profile_ids(reauth), :callback_required) or
          SuiteSupport.fetch(reauth, :state_required, false),
        "manifest.auth.reauth.state_required must be true when reauth callback profiles are declared"
      ),
      SuiteSupport.check(
        "manifest.auth.reauth.pkce_supported.when_pkce_profiles_exist",
        not any_profile?(profiles, reauth_profile_ids(reauth), :pkce_required) or
          SuiteSupport.fetch(reauth, :pkce_supported, false),
        "manifest.auth.reauth.pkce_supported must be true when reauth PKCE profiles are declared"
      )
    ]
  end

  defp required_scopes(permissions) do
    permissions
    |> SuiteSupport.fetch(:required_scopes, [])
    |> normalize_string_list()
  end

  defp trigger_secret_names(trigger) do
    verification_secret_name =
      trigger
      |> Map.get(:verification, %{})
      |> SuiteSupport.fetch(:secret_name)
      |> normalize_optional_secret_name()

    secret_requirements =
      trigger
      |> Map.get(:secret_requirements, [])
      |> normalize_string_list()

    secret_requirements ++ verification_secret_name
  end

  defp normalize_optional_secret_name(nil), do: []
  defp normalize_optional_secret_name(secret_name), do: normalize_string_list([secret_name])

  defp normalize_string_list(values) when is_list(values) do
    values
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_string_list(_values), do: []

  defp normalize_atom_list(values) when is_list(values) do
    values
    |> Enum.map(fn
      value when is_atom(value) -> value
      value when is_binary(value) -> String.to_atom(value)
      value -> value
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_atom_list(_values), do: []

  defp union_profile_string_values(profiles, key) do
    profiles
    |> Enum.flat_map(&normalize_string_list(Map.get(&1, key, [])))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp union_profile_atom_values(profiles, key) do
    profiles
    |> Enum.flat_map(&normalize_atom_list(Map.get(&1, key, [])))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp profile_ids(profiles, key) do
    profiles
    |> Enum.filter(&(Map.get(&1, key) == true))
    |> Enum.map(&Map.get(&1, :id))
    |> normalize_string_list()
  end

  defp declared_profile_ids?(contract_map, known_profile_ids) do
    profile_ids =
      contract_map
      |> SuiteSupport.fetch(:profiles, [])
      |> normalize_string_list()

    profile_ids -- normalize_string_list(known_profile_ids) == []
  end

  defp install_profile_ids(install),
    do: install |> SuiteSupport.fetch(:profiles, []) |> normalize_string_list()

  defp reauth_profile_ids(reauth),
    do: reauth |> SuiteSupport.fetch(:profiles, []) |> normalize_string_list()

  defp any_profile?(profiles, profile_ids, key) do
    Enum.any?(profiles, fn profile ->
      Map.get(profile, :id) in profile_ids and Map.get(profile, key) == true
    end)
  end

  defp default_profile(%AuthSpec{} = auth) do
    Enum.find(auth.supported_profiles, &(&1.id == auth.default_profile))
  end

  defp profile_checks(profile) do
    context = %{
      profile: profile,
      profile_id: Map.get(profile, :id, "unknown"),
      auth_type: Map.get(profile, :auth_type),
      install_required: Map.get(profile, :install_required),
      grant_types: Map.get(profile, :grant_types),
      callback_required: Map.get(profile, :callback_required, false),
      pkce_required: Map.get(profile, :pkce_required, false),
      refresh_supported: Map.get(profile, :refresh_supported, false),
      durable_secret_fields: normalize_string_list(Map.get(profile, :durable_secret_fields, [])),
      lease_fields: normalize_string_list(Map.get(profile, :lease_fields, [])),
      management_modes: normalize_atom_list(Map.get(profile, :management_modes, [])),
      external_secret_supported: Map.get(profile, :external_secret_supported, false),
      external_secret_lease_fields:
        normalize_string_list(Map.get(profile, :external_secret_lease_fields, []))
    }

    profile_identity_checks(context) ++
      profile_install_checks(context) ++
      profile_secret_projection_checks(context)
  end

  defp profile_identity_checks(context) do
    [
      SuiteSupport.check(
        "manifest.auth.profile.#{context.profile_id}.required_fields.present",
        required_profile_fields_present?(context.profile),
        "each auth profile must declare id, auth_type, subject_kind, install_required, durable_secret_fields, lease_fields, and management_modes"
      ),
      SuiteSupport.check(
        "manifest.auth.profile.#{context.profile_id}.grant_types.present",
        context.auth_type == :none or normalize_grant_types(context.grant_types) != [],
        "credential-bearing auth profiles must declare grant_types"
      ),
      SuiteSupport.check(
        "manifest.auth.profile.#{context.profile_id}.lease_fields.present",
        context.auth_type == :none or context.lease_fields != [],
        "credential-bearing auth profiles must declare at least one lease_field"
      )
    ]
  end

  defp profile_install_checks(context) do
    [
      SuiteSupport.check(
        "manifest.auth.profile.#{context.profile_id}.callback_requires_install",
        not context.callback_required or context.install_required == true,
        "callback_required profiles must also require install"
      ),
      SuiteSupport.check(
        "manifest.auth.profile.#{context.profile_id}.pkce_requires_callback",
        not context.pkce_required or
          (context.callback_required and
             :authorization_code in normalize_grant_types(context.grant_types)),
        "pkce_required profiles must also declare callback_required and include :authorization_code grant_types"
      ),
      SuiteSupport.check(
        "manifest.auth.profile.#{context.profile_id}.refresh_material.available",
        not context.refresh_supported or
          "refresh_token" in context.durable_secret_fields or
          "refresh_token" in context.external_secret_lease_fields,
        "refresh_supported profiles must expose refresh material durably or through external_secret_lease_fields"
      )
    ]
  end

  defp profile_secret_projection_checks(context) do
    [
      SuiteSupport.check(
        "manifest.auth.profile.#{context.profile_id}.external_secret_flag_matches_management_modes",
        context.external_secret_supported == :external_secret in context.management_modes,
        "external_secret_supported must match whether :external_secret is declared in management_modes"
      ),
      SuiteSupport.check(
        "manifest.auth.profile.#{context.profile_id}.external_secret_fields.when_supported",
        context.external_secret_supported or context.external_secret_lease_fields == [],
        "external_secret_lease_fields may only be declared when external_secret_supported is true"
      ),
      SuiteSupport.check(
        "manifest.auth.profile.#{context.profile_id}.external_secret_subset",
        context.external_secret_lease_fields -- context.lease_fields == [],
        "external_secret_lease_fields must be a subset of lease_fields"
      ),
      SuiteSupport.check(
        "manifest.auth.profile.#{context.profile_id}.lease_projection.explicit",
        lease_projection_valid?(
          context.external_secret_supported,
          context.lease_fields,
          context.durable_secret_fields,
          context.external_secret_lease_fields
        ),
        "lease_fields must be durable or explicitly covered by external_secret_lease_fields"
      ),
      SuiteSupport.check(
        "manifest.auth.profile.#{context.profile_id}.none_posture.explicit",
        context.auth_type != :none or
          none_profile_valid?(
            context.profile,
            context.durable_secret_fields,
            context.lease_fields,
            context.management_modes
          ),
        "auth_type :none profiles must explicitly declare no-install, no-secret, and no-management posture"
      )
    ]
  end

  defp required_profile_fields_present?(profile) do
    Enum.all?(
      [
        :id,
        :auth_type,
        :subject_kind,
        :install_required,
        :durable_secret_fields,
        :lease_fields,
        :management_modes
      ],
      &Map.has_key?(profile, &1)
    )
  end

  defp normalize_grant_types(values) when is_list(values) do
    values
    |> Enum.map(fn
      value when is_atom(value) -> value
      value when is_binary(value) -> String.to_atom(value)
      value -> value
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_grant_types(_values), do: []

  defp lease_projection_valid?(
         false,
         lease_fields,
         durable_secret_fields,
         _external_secret_lease_fields
       ),
       do: lease_fields -- durable_secret_fields == []

  defp lease_projection_valid?(
         true,
         lease_fields,
         durable_secret_fields,
         external_secret_lease_fields
       ) do
    (lease_fields -- durable_secret_fields) -- external_secret_lease_fields == []
  end

  defp none_profile_valid?(profile, durable_secret_fields, lease_fields, management_modes) do
    Map.get(profile, :install_required) == false and durable_secret_fields == [] and
      lease_fields == [] and management_modes == [] and
      normalize_grant_types(Map.get(profile, :grant_types)) == []
  end

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_map), do: %{}
end
