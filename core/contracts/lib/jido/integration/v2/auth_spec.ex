defmodule Jido.Integration.V2.AuthSpec do
  @moduledoc """
  Authored auth contract for a connector manifest.
  """

  alias Jido.Integration.V2.Contracts

  @binding_kinds [:connection_id, :tenant, :none]
  @auth_types [:oauth2, :api_token, :session_token, :none]

  @enforce_keys [
    :binding_kind,
    :auth_type,
    :install,
    :reauth,
    :requested_scopes,
    :lease_fields,
    :secret_names
  ]
  defstruct [
    :binding_kind,
    :auth_type,
    :install,
    :reauth,
    :requested_scopes,
    :lease_fields,
    :secret_names,
    metadata: %{}
  ]

  @type binding_kind :: :connection_id | :tenant | :none
  @type auth_type :: :oauth2 | :api_token | :session_token | :none

  @type t :: %__MODULE__{
          binding_kind: binding_kind(),
          auth_type: auth_type(),
          install: map(),
          reauth: map(),
          requested_scopes: [String.t()],
          lease_fields: [String.t()],
          secret_names: [String.t()],
          metadata: map()
        }

  @spec new!(map() | t()) :: t()
  def new!(%__MODULE__{} = auth_spec), do: auth_spec

  def new!(attrs) when is_map(attrs) do
    attrs = Map.new(attrs)

    struct!(__MODULE__, %{
      binding_kind: validate_binding_kind!(Contracts.fetch!(attrs, :binding_kind)),
      auth_type: validate_auth_type!(Contracts.fetch!(attrs, :auth_type)),
      install: Contracts.validate_map!(Contracts.fetch!(attrs, :install), "auth.install"),
      reauth: Contracts.validate_map!(Contracts.fetch!(attrs, :reauth), "auth.reauth"),
      requested_scopes:
        Contracts.normalize_string_list!(
          Contracts.fetch!(attrs, :requested_scopes),
          "auth.requested_scopes"
        ),
      lease_fields:
        Contracts.normalize_string_list!(
          Contracts.fetch!(attrs, :lease_fields),
          "auth.lease_fields"
        ),
      secret_names:
        Contracts.normalize_string_list!(
          Contracts.fetch!(attrs, :secret_names),
          "auth.secret_names"
        ),
      metadata: Contracts.validate_map!(Map.get(attrs, :metadata, %{}), "auth.metadata")
    })
  end

  def new!(attrs) do
    raise ArgumentError, "auth spec must be a map, got: #{inspect(attrs)}"
  end

  defp validate_binding_kind!(binding_kind) when binding_kind in @binding_kinds, do: binding_kind

  defp validate_binding_kind!(binding_kind) when is_binary(binding_kind) do
    normalize_enum_string!(binding_kind, @binding_kinds, "auth.binding_kind")
  end

  defp validate_binding_kind!(binding_kind) do
    raise ArgumentError, "invalid auth.binding_kind: #{inspect(binding_kind)}"
  end

  defp validate_auth_type!(auth_type) when auth_type in @auth_types, do: auth_type

  defp validate_auth_type!(auth_type) when is_binary(auth_type) do
    normalize_enum_string!(auth_type, @auth_types, "auth.auth_type")
  end

  defp validate_auth_type!(auth_type) do
    raise ArgumentError, "invalid auth.auth_type: #{inspect(auth_type)}"
  end

  defp normalize_enum_string!(value, allowed, field_name) do
    case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
      nil -> raise ArgumentError, "invalid #{field_name}: #{inspect(value)}"
      enum_value -> enum_value
    end
  end
end
