defmodule Jido.Integration.V2.AuthSpec do
  @moduledoc """
  Authored auth contract for a connector manifest.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @binding_kinds [:connection_id, :tenant, :none]
  @auth_types [:oauth2, :api_token, :session_token, :app_installation, :none]
  @subject_kinds [:user, :workspace, :app, :installation, :tenant, :none]
  @profile_management_modes [:hosted, :manual, :external_secret, :provider_app]
  @legacy_default_profile "default"

  @schema Zoi.struct(
            __MODULE__,
            %{
              binding_kind: Contracts.enumish_schema(@binding_kinds, "auth.binding_kind"),
              auth_type:
                Contracts.enumish_schema(@auth_types, "auth.auth_type")
                |> Zoi.nullish()
                |> Zoi.optional(),
              supported_profiles: Zoi.list(Contracts.any_map_schema()) |> Zoi.default([]),
              default_profile:
                Contracts.non_empty_string_schema("auth.default_profile")
                |> Zoi.nullish()
                |> Zoi.optional(),
              install: Contracts.any_map_schema() |> Zoi.default(%{}),
              reauth: Contracts.any_map_schema() |> Zoi.default(%{}),
              management_modes: Zoi.list(Zoi.atom()) |> Zoi.nullish() |> Zoi.optional(),
              requested_scopes:
                Contracts.string_list_schema("auth.requested_scopes")
                |> Zoi.nullish()
                |> Zoi.optional(),
              durable_secret_fields:
                Contracts.string_list_schema("auth.durable_secret_fields")
                |> Zoi.nullish()
                |> Zoi.optional(),
              lease_fields:
                Contracts.string_list_schema("auth.lease_fields")
                |> Zoi.nullish()
                |> Zoi.optional(),
              secret_names:
                Contracts.string_list_schema("auth.secret_names")
                |> Zoi.nullish()
                |> Zoi.optional(),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type binding_kind :: :connection_id | :tenant | :none
  @type auth_type :: :oauth2 | :api_token | :session_token | :app_installation | :none

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = auth_spec), do: validate(auth_spec)

  def new(attrs) do
    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&validate/1)
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = auth_spec),
    do: auth_spec |> validate() |> then(fn {:ok, value} -> value end)

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  @spec fetch_profile(t(), String.t()) :: map() | nil
  def fetch_profile(%__MODULE__{supported_profiles: profiles}, profile_id)
      when is_binary(profile_id) do
    Enum.find(profiles, &(&1.id == profile_id))
  end

  @spec default_profile(t()) :: map() | nil
  def default_profile(%__MODULE__{} = auth_spec) do
    fetch_profile(auth_spec, auth_spec.default_profile)
  end

  defp validate(%__MODULE__{} = auth_spec) do
    profiles = normalize_profiles(auth_spec)
    default_profile_id = normalize_default_profile(auth_spec.default_profile, profiles)
    default_profile = Enum.find(profiles, &(&1.id == default_profile_id))

    requested_scopes =
      auth_spec.requested_scopes
      |> normalize_optional_string_list(union_profile_values(profiles, :required_scopes))

    durable_secret_fields =
      auth_spec.durable_secret_fields
      |> normalize_optional_string_list(union_profile_values(profiles, :durable_secret_fields))

    lease_fields =
      auth_spec.lease_fields
      |> normalize_optional_string_list(union_profile_values(profiles, :lease_fields))

    management_modes =
      auth_spec.management_modes
      |> normalize_optional_management_modes(union_profile_values(profiles, :management_modes))

    install = normalize_install(auth_spec.install, profiles)
    reauth = normalize_reauth(auth_spec.reauth, profiles)
    secret_names = normalize_optional_string_list(auth_spec.secret_names, [])
    metadata = normalize_map(auth_spec.metadata, "auth.metadata")
    auth_type = default_profile && default_profile.auth_type

    validate_requested_scopes!(requested_scopes, profiles)

    {:ok,
     %__MODULE__{
       auth_spec
       | auth_type: auth_type,
         supported_profiles: profiles,
         default_profile: default_profile_id,
         install: install,
         reauth: reauth,
         management_modes: management_modes,
         requested_scopes: requested_scopes,
         durable_secret_fields: durable_secret_fields,
         lease_fields: lease_fields,
         secret_names: secret_names,
         metadata: metadata
     }}
  end

  defp normalize_profiles(%__MODULE__{supported_profiles: [], auth_type: auth_type} = auth_spec)
       when not is_nil(auth_type) do
    [legacy_profile(auth_spec)]
  end

  defp normalize_profiles(%__MODULE__{supported_profiles: profiles}) when is_list(profiles) do
    profiles
    |> Enum.map(&normalize_profile/1)
    |> ensure_unique_profile_ids!()
  end

  defp normalize_profiles(_auth_spec) do
    raise ArgumentError, "auth.supported_profiles must be a list"
  end

  defp legacy_profile(%__MODULE__{} = auth_spec) do
    auth_type = auth_spec.auth_type
    install = normalize_map(auth_spec.install, "auth.install")
    reauth = normalize_map(auth_spec.reauth, "auth.reauth")
    requested_scopes = normalize_string_list(auth_spec.requested_scopes, "auth.requested_scopes")
    lease_fields = normalize_string_list(auth_spec.lease_fields, "auth.lease_fields")

    profile =
      %{
        id: @legacy_default_profile,
        auth_type: auth_type,
        subject_kind: legacy_subject_kind(auth_type),
        install_required: Contracts.get(install, :required, auth_type != :none),
        durable_secret_fields:
          normalize_optional_string_list(
            Contracts.get(auth_spec, :durable_secret_fields),
            lease_fields
          ),
        lease_fields: lease_fields,
        management_modes:
          normalize_optional_management_modes(
            Contracts.get(auth_spec, :management_modes),
            legacy_management_modes(auth_type, install)
          ),
        required_scopes: requested_scopes,
        callback_required: Contracts.get(install, :hosted_callback_supported, false),
        pkce_required: Contracts.get(install, :pkce_supported, false),
        refresh_supported: false,
        revoke_supported: false,
        reauth_supported: Contracts.get(reauth, :supported, false),
        external_secret_supported: false,
        external_secret_lease_fields: [],
        docs_refs: [],
        metadata: %{}
      }

    grant_types =
      case auth_type do
        :oauth2 -> [:authorization_code]
        :api_token -> [:manual_token]
        :session_token -> [:manual_token]
        :app_installation -> [:manual_token]
        :none -> nil
      end

    profile
    |> maybe_put(:grant_types, grant_types)
    |> normalize_profile()
  end

  defp normalize_profile(profile) when is_map(profile) do
    auth_type =
      normalize_auth_type(
        fetch_required(profile, :auth_type, "auth.supported_profiles.auth_type")
      )

    normalized = %{
      id: fetch_required_string(profile, :id, "auth.supported_profiles.id"),
      auth_type: auth_type,
      subject_kind:
        normalize_subject_kind(
          fetch_required(profile, :subject_kind, "auth.supported_profiles.subject_kind")
        ),
      install_required:
        normalize_boolean!(
          fetch_required(profile, :install_required, "auth.supported_profiles.install_required"),
          "auth.supported_profiles.install_required"
        ),
      durable_secret_fields:
        normalize_string_list(
          fetch_required(
            profile,
            :durable_secret_fields,
            "auth.supported_profiles.durable_secret_fields"
          ),
          "auth.supported_profiles.durable_secret_fields"
        ),
      lease_fields:
        normalize_string_list(
          fetch_required(profile, :lease_fields, "auth.supported_profiles.lease_fields"),
          "auth.supported_profiles.lease_fields"
        ),
      management_modes:
        normalize_management_modes!(
          fetch_required(profile, :management_modes, "auth.supported_profiles.management_modes"),
          "auth.supported_profiles.management_modes"
        ),
      callback_required:
        normalize_boolean!(
          Contracts.get(profile, :callback_required, false),
          "auth.supported_profiles.callback_required"
        ),
      pkce_required:
        normalize_boolean!(
          Contracts.get(profile, :pkce_required, false),
          "auth.supported_profiles.pkce_required"
        ),
      refresh_supported:
        normalize_boolean!(
          Contracts.get(profile, :refresh_supported, false),
          "auth.supported_profiles.refresh_supported"
        ),
      revoke_supported:
        normalize_boolean!(
          Contracts.get(profile, :revoke_supported, false),
          "auth.supported_profiles.revoke_supported"
        ),
      reauth_supported:
        normalize_boolean!(
          Contracts.get(profile, :reauth_supported, false),
          "auth.supported_profiles.reauth_supported"
        ),
      external_secret_supported:
        normalize_boolean!(
          Contracts.get(profile, :external_secret_supported, false),
          "auth.supported_profiles.external_secret_supported"
        ),
      external_secret_lease_fields:
        normalize_string_list(
          Contracts.get(profile, :external_secret_lease_fields, []),
          "auth.supported_profiles.external_secret_lease_fields"
        ),
      required_scopes:
        normalize_string_list(
          Contracts.get(profile, :required_scopes, []),
          "auth.supported_profiles.required_scopes"
        ),
      docs_refs:
        normalize_string_list(
          Contracts.get(profile, :docs_refs, []),
          "auth.supported_profiles.docs_refs"
        ),
      metadata:
        normalize_map(Contracts.get(profile, :metadata, %{}), "auth.supported_profiles.metadata")
    }

    grant_types = normalize_grant_types(auth_type, Contracts.get(profile, :grant_types))
    validate_profile!(Map.put(normalized, :grant_types, grant_types))
  end

  defp normalize_profile(profile) do
    raise ArgumentError,
          "auth.supported_profiles entries must be maps, got: #{inspect(profile)}"
  end

  defp validate_profile!(%{auth_type: :none} = profile) do
    cond do
      profile.install_required != false ->
        raise ArgumentError, "auth_type :none profiles must set install_required to false"

      profile.durable_secret_fields != [] ->
        raise ArgumentError, "auth_type :none profiles must declare no durable_secret_fields"

      profile.lease_fields != [] ->
        raise ArgumentError, "auth_type :none profiles must declare no lease_fields"

      profile.management_modes != [] ->
        raise ArgumentError, "auth_type :none profiles must declare no management_modes"

      not is_nil(profile.grant_types) and profile.grant_types != [] ->
        raise ArgumentError, "auth_type :none profiles must not declare grant_types"

      true ->
        Map.put(profile, :grant_types, nil)
    end
  end

  defp validate_profile!(profile) do
    validate_grant_types!(profile)
    validate_lease_fields!(profile)
    validate_callback_install!(profile)
    validate_pkce!(profile)
    validate_refresh_material!(profile)
    validate_external_secret_fields!(profile)
    profile
  end

  defp validate_grant_types!(%{grant_types: grant_types}) when grant_types in [nil, []] do
    raise ArgumentError, "credential-bearing profiles must declare grant_types"
  end

  defp validate_grant_types!(_profile), do: :ok

  defp validate_lease_fields!(%{lease_fields: []}) do
    raise ArgumentError, "credential-bearing profiles must declare at least one lease_field"
  end

  defp validate_lease_fields!(_profile), do: :ok

  defp validate_callback_install!(%{callback_required: true, install_required: false}) do
    raise ArgumentError, "callback_required profiles must also require install"
  end

  defp validate_callback_install!(_profile), do: :ok

  defp validate_pkce!(%{pkce_required: true, callback_required: false}) do
    raise ArgumentError, "pkce_required profiles must also declare callback_required"
  end

  defp validate_pkce!(%{pkce_required: true, grant_types: grant_types}) do
    if :authorization_code in grant_types do
      :ok
    else
      raise ArgumentError, "pkce_required profiles must include :authorization_code grant_types"
    end
  end

  defp validate_pkce!(_profile), do: :ok

  defp validate_refresh_material!(%{
         refresh_supported: true,
         durable_secret_fields: durable_secret_fields,
         external_secret_supported: external_secret_supported,
         external_secret_lease_fields: external_secret_lease_fields
       }) do
    if refresh_material_available?(
         durable_secret_fields,
         external_secret_supported,
         external_secret_lease_fields
       ) do
      :ok
    else
      raise ArgumentError,
            "refresh_supported profiles must expose refresh material durably or through explicit external secret lease fields"
    end
  end

  defp validate_refresh_material!(_profile), do: :ok

  defp validate_external_secret_fields!(%{
         external_secret_supported: false,
         lease_fields: lease_fields,
         durable_secret_fields: durable_secret_fields,
         external_secret_lease_fields: external_secret_lease_fields
       }) do
    validate_external_secret_subset!(external_secret_lease_fields, lease_fields)

    if lease_fields -- durable_secret_fields == [] do
      :ok
    else
      raise ArgumentError,
            "lease_fields must be a subset of durable_secret_fields unless external_secret_supported is true"
    end
  end

  defp validate_external_secret_fields!(%{
         external_secret_supported: true,
         lease_fields: lease_fields,
         durable_secret_fields: durable_secret_fields,
         external_secret_lease_fields: external_secret_lease_fields
       }) do
    validate_external_secret_subset!(external_secret_lease_fields, lease_fields)

    validate_external_secret_coverage!(
      lease_fields,
      durable_secret_fields,
      external_secret_lease_fields
    )
  end

  defp validate_external_secret_subset!(external_secret_lease_fields, lease_fields) do
    if external_secret_lease_fields -- lease_fields == [] do
      :ok
    else
      raise ArgumentError,
            "external_secret_lease_fields must be a subset of lease_fields"
    end
  end

  defp validate_external_secret_coverage!(
         lease_fields,
         durable_secret_fields,
         external_secret_lease_fields
       ) do
    missing_external_fields =
      (lease_fields -- durable_secret_fields) -- external_secret_lease_fields

    if missing_external_fields == [] do
      :ok
    else
      raise ArgumentError,
            "every lease_field not stored durably must be declared in external_secret_lease_fields"
    end
  end

  defp normalize_default_profile(nil, [profile | _profiles]), do: profile.id

  defp normalize_default_profile(profile_id, profiles) when is_binary(profile_id) do
    profile_id = Contracts.validate_non_empty_string!(profile_id, "auth.default_profile")

    if Enum.any?(profiles, &(&1.id == profile_id)) do
      profile_id
    else
      raise ArgumentError,
            "auth.default_profile must refer to a declared supported_profile, got: #{inspect(profile_id)}"
    end
  end

  defp normalize_default_profile(_profile_id, []) do
    raise ArgumentError, "auth.supported_profiles must declare at least one profile"
  end

  defp normalize_install(install, profiles) do
    install = normalize_map(install, "auth.install")
    default_profiles = profile_ids(profiles, & &1.install_required)

    normalized = %{
      required:
        normalize_boolean!(
          Contracts.get(install, :required, default_profiles != []),
          "auth.install.required"
        ),
      profiles:
        normalize_optional_string_list(
          Contracts.get(install, :profiles),
          default_profiles
        ),
      hosted_callback_supported:
        normalize_boolean!(
          Contracts.get(install, :hosted_callback_supported, false),
          "auth.install.hosted_callback_supported"
        ),
      callback_route_kind:
        normalize_optional_string(
          Contracts.get(install, :callback_route_kind),
          "auth.install.callback_route_kind"
        ),
      state_required:
        normalize_boolean!(
          Contracts.get(
            install,
            :state_required,
            profile_value?(profiles, :callback_required, true)
          ),
          "auth.install.state_required"
        ),
      pkce_supported:
        normalize_boolean!(
          Contracts.get(install, :pkce_supported, profile_value?(profiles, :pkce_required, true)),
          "auth.install.pkce_supported"
        ),
      expires_in_seconds:
        normalize_optional_positive_integer(
          Contracts.get(install, :expires_in_seconds),
          "auth.install.expires_in_seconds"
        ),
      metadata: normalize_map(Contracts.get(install, :metadata, %{}), "auth.install.metadata")
    }

    validate_declared_profiles!(normalized.profiles, profiles, "auth.install.profiles")

    if normalized.required or normalized.profiles == [] do
      normalized
    else
      raise ArgumentError,
            "auth.install.profiles cannot be declared when auth.install.required is false"
    end
  end

  defp normalize_reauth(reauth, profiles) do
    reauth = normalize_map(reauth, "auth.reauth")
    default_profiles = profile_ids(profiles, & &1.reauth_supported)

    normalized = %{
      supported:
        normalize_boolean!(
          Contracts.get(reauth, :supported, default_profiles != []),
          "auth.reauth.supported"
        ),
      profiles:
        normalize_optional_string_list(
          Contracts.get(reauth, :profiles),
          default_profiles
        ),
      hosted_callback_supported:
        normalize_boolean!(
          Contracts.get(reauth, :hosted_callback_supported, false),
          "auth.reauth.hosted_callback_supported"
        ),
      state_required:
        normalize_boolean!(
          Contracts.get(
            reauth,
            :state_required,
            profile_value?(profiles, :callback_required, true)
          ),
          "auth.reauth.state_required"
        ),
      pkce_supported:
        normalize_boolean!(
          Contracts.get(reauth, :pkce_supported, profile_value?(profiles, :pkce_required, true)),
          "auth.reauth.pkce_supported"
        ),
      metadata: normalize_map(Contracts.get(reauth, :metadata, %{}), "auth.reauth.metadata")
    }

    validate_declared_profiles!(normalized.profiles, profiles, "auth.reauth.profiles")

    if normalized.supported do
      normalized
    else
      %{normalized | profiles: []}
    end
  end

  defp validate_requested_scopes!(requested_scopes, profiles) do
    profile_scopes = union_profile_values(profiles, :required_scopes)

    case profile_scopes -- requested_scopes do
      [] ->
        :ok

      missing ->
        raise ArgumentError,
              "auth.requested_scopes must cover profile required_scopes, missing #{inspect(missing)}"
    end
  end

  defp ensure_unique_profile_ids!(profiles) do
    ids = Enum.map(profiles, & &1.id)

    if ids == Enum.uniq(ids) do
      profiles
    else
      raise ArgumentError, "auth.supported_profiles must use unique ids"
    end
  end

  defp validate_declared_profiles!(declared_profile_ids, profiles, field_name) do
    known_profile_ids = Enum.map(profiles, & &1.id)

    case declared_profile_ids -- known_profile_ids do
      [] ->
        :ok

      missing ->
        raise ArgumentError,
              "#{field_name} must refer to declared supported_profiles, missing #{inspect(missing)}"
    end
  end

  defp profile_ids(profiles, predicate) do
    profiles
    |> Enum.filter(predicate)
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  defp profile_value?(profiles, key, value) do
    Enum.any?(profiles, &(Map.get(&1, key) == value))
  end

  defp union_profile_values(profiles, key) do
    profiles
    |> Enum.flat_map(&Map.get(&1, key, []))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_auth_type(auth_type),
    do: validate_enum!(auth_type, @auth_types, "auth.auth_type")

  defp normalize_subject_kind(subject_kind),
    do: validate_enum!(subject_kind, @subject_kinds, "auth.subject_kind")

  defp normalize_grant_types(:none, nil), do: nil
  defp normalize_grant_types(:none, []), do: nil

  defp normalize_grant_types(_auth_type, nil), do: nil

  defp normalize_grant_types(_auth_type, grant_types) when is_list(grant_types) do
    grant_types
    |> Enum.map(&normalize_grant_type/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_grant_types(_auth_type, grant_types) do
    raise ArgumentError,
          "auth.supported_profiles.grant_types must be a list, got: #{inspect(grant_types)}"
  end

  defp normalize_grant_type(grant_type) when is_atom(grant_type), do: grant_type

  defp normalize_grant_type(grant_type) when is_binary(grant_type) do
    String.to_existing_atom(grant_type)
  rescue
    ArgumentError ->
      String.to_atom(grant_type)
  end

  defp normalize_grant_type(grant_type) do
    raise ArgumentError, "invalid grant_type: #{inspect(grant_type)}"
  end

  defp normalize_management_modes!(management_modes, field_name) when is_list(management_modes) do
    management_modes
    |> Enum.map(&validate_enum!(&1, @profile_management_modes, field_name))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_management_modes!(management_modes, field_name) do
    raise ArgumentError, "#{field_name} must be a list, got: #{inspect(management_modes)}"
  end

  defp normalize_optional_management_modes(nil, default),
    do: normalize_management_modes!(default, "auth.management_modes")

  defp normalize_optional_management_modes(management_modes, _default),
    do: normalize_management_modes!(management_modes, "auth.management_modes")

  defp normalize_string_list(values, field_name) when is_list(values) do
    values
    |> Enum.map(&Contracts.validate_non_empty_string!(to_string(&1), field_name))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_string_list(values, field_name) do
    raise ArgumentError, "#{field_name} must be a list, got: #{inspect(values)}"
  end

  defp normalize_optional_string_list(nil, default),
    do: normalize_string_list(default, "auth.defaults")

  defp normalize_optional_string_list(values, _default),
    do: normalize_string_list(values, "auth.defaults")

  defp normalize_map(map, _field_name) when is_map(map), do: Map.new(map)

  defp normalize_map(value, field_name) do
    raise ArgumentError, "#{field_name} must be a map, got: #{inspect(value)}"
  end

  defp normalize_boolean!(value, _field_name) when is_boolean(value), do: value

  defp normalize_boolean!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a boolean, got: #{inspect(value)}"
  end

  defp normalize_optional_positive_integer(nil, _field_name), do: nil

  defp normalize_optional_positive_integer(value, _field_name)
       when is_integer(value) and value > 0,
       do: value

  defp normalize_optional_positive_integer(value, field_name) do
    raise ArgumentError, "#{field_name} must be a positive integer or nil, got: #{inspect(value)}"
  end

  defp normalize_optional_string(nil, _field_name), do: nil

  defp normalize_optional_string(value, field_name) do
    Contracts.validate_non_empty_string!(to_string(value), field_name)
  end

  defp validate_enum!(value, allowed, field_name) when is_atom(value) do
    if value in allowed do
      value
    else
      raise ArgumentError, "invalid #{field_name}: #{inspect(value)}"
    end
  end

  defp validate_enum!(value, allowed, field_name) when is_binary(value) do
    value
    |> String.to_existing_atom()
    |> validate_enum!(allowed, field_name)
  rescue
    _error in ArgumentError ->
      reraise ArgumentError.exception("invalid #{field_name}: #{inspect(value)}"), __STACKTRACE__
  end

  defp validate_enum!(value, _allowed, field_name) do
    raise ArgumentError, "invalid #{field_name}: #{inspect(value)}"
  end

  defp fetch_required(map, key, field_name) do
    case Contracts.get(map, key) do
      nil -> raise ArgumentError, "#{field_name} is required"
      value -> value
    end
  end

  defp fetch_required_string(map, key, field_name) do
    map
    |> fetch_required(key, field_name)
    |> Contracts.validate_non_empty_string!(field_name)
  end

  defp refresh_material_available?(durable_secret_fields, true, external_secret_lease_fields) do
    "refresh_token" in durable_secret_fields or "refresh_token" in external_secret_lease_fields
  end

  defp refresh_material_available?(durable_secret_fields, false, _external_secret_lease_fields) do
    "refresh_token" in durable_secret_fields
  end

  defp legacy_subject_kind(:oauth2), do: :user
  defp legacy_subject_kind(:api_token), do: :user
  defp legacy_subject_kind(:session_token), do: :user
  defp legacy_subject_kind(:app_installation), do: :installation
  defp legacy_subject_kind(:none), do: :none

  defp legacy_management_modes(:none, _install), do: []
  defp legacy_management_modes(_auth_type, _install), do: [:manual]

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
