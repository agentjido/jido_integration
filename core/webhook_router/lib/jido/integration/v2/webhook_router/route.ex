defmodule Jido.Integration.V2.WebhookRouter.Route do
  @moduledoc """
  Durable hosted-webhook route metadata.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.CredentialRef

  @typedoc """
  Explicit hosted callback topology for a registered route.
  """
  @type callback_topology :: :dynamic_per_install | :static_per_app

  @type status :: :active | :disabled | :revoked
  @type validator_ref :: {module(), atom()} | nil
  @type secret_ref :: %{credential_ref: CredentialRef.t(), secret_key: String.t()}
  @type verification :: %{
          optional(:algorithm) => atom(),
          optional(:signature_header) => String.t(),
          optional(:secret) => String.t(),
          optional(:secret_ref) => secret_ref()
        }

  @enforce_keys [
    :route_id,
    :connector_id,
    :trigger_id,
    :capability_id,
    :signal_type,
    :signal_source,
    :callback_topology,
    :status,
    :revision,
    :inserted_at,
    :updated_at
  ]
  defstruct [
    :route_id,
    :connector_id,
    :tenant_id,
    :connection_id,
    :install_id,
    :trigger_id,
    :capability_id,
    :signal_type,
    :signal_source,
    :callback_topology,
    :validator,
    :verification,
    status: :active,
    tenant_resolution_keys: [],
    tenant_resolution: %{},
    delivery_id_headers: [],
    dedupe_ttl_seconds: 86_400,
    revision: 1,
    inserted_at: nil,
    updated_at: nil
  ]

  @type t :: %__MODULE__{
          route_id: String.t(),
          connector_id: String.t(),
          tenant_id: String.t() | nil,
          connection_id: String.t() | nil,
          install_id: String.t() | nil,
          trigger_id: String.t(),
          capability_id: String.t(),
          signal_type: String.t(),
          signal_source: String.t(),
          callback_topology: callback_topology(),
          validator: validator_ref(),
          verification: verification() | nil,
          status: status(),
          tenant_resolution_keys: [String.t()],
          tenant_resolution: map(),
          delivery_id_headers: [String.t()],
          dedupe_ttl_seconds: pos_integer(),
          revision: pos_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    attrs = Map.new(attrs)
    inserted_at = Contracts.get(attrs, :inserted_at, Contracts.now())
    topology = normalize_topology(Contracts.fetch!(attrs, :callback_topology))
    tenant_resolution = normalize_resolution_map(Contracts.get(attrs, :tenant_resolution, %{}))

    tenant_resolution_keys =
      Contracts.get(attrs, :tenant_resolution_keys, Map.keys(tenant_resolution))
      |> normalize_resolution_keys()

    route =
      struct!(__MODULE__, %{
        route_id:
          Contracts.validate_non_empty_string!(
            Contracts.get(attrs, :route_id, Contracts.next_id("webhook_route")),
            "route_id"
          ),
        connector_id:
          Contracts.validate_non_empty_string!(
            Contracts.fetch!(attrs, :connector_id),
            "connector_id"
          ),
        tenant_id: normalize_optional_string(Contracts.get(attrs, :tenant_id), "tenant_id"),
        connection_id:
          normalize_optional_string(Contracts.get(attrs, :connection_id), "connection_id"),
        install_id: normalize_optional_string(Contracts.get(attrs, :install_id), "install_id"),
        trigger_id:
          Contracts.validate_non_empty_string!(Contracts.fetch!(attrs, :trigger_id), "trigger_id"),
        capability_id:
          Contracts.validate_non_empty_string!(
            Contracts.fetch!(attrs, :capability_id),
            "capability_id"
          ),
        signal_type:
          Contracts.validate_non_empty_string!(
            Contracts.fetch!(attrs, :signal_type),
            "signal_type"
          ),
        signal_source:
          Contracts.validate_non_empty_string!(
            Contracts.fetch!(attrs, :signal_source),
            "signal_source"
          ),
        callback_topology: topology,
        validator: normalize_validator(Contracts.get(attrs, :validator)),
        verification: normalize_verification(Contracts.get(attrs, :verification)),
        status: normalize_status(Contracts.get(attrs, :status, :active)),
        tenant_resolution_keys: tenant_resolution_keys,
        tenant_resolution: tenant_resolution,
        delivery_id_headers: normalize_headers(Contracts.get(attrs, :delivery_id_headers, [])),
        dedupe_ttl_seconds: normalize_ttl(Contracts.get(attrs, :dedupe_ttl_seconds, 86_400)),
        revision: normalize_revision(Contracts.get(attrs, :revision, 1)),
        inserted_at: inserted_at,
        updated_at: Contracts.get(attrs, :updated_at, inserted_at)
      })

    validate_route!(route)
  end

  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{status: :active}), do: true
  def active?(%__MODULE__{}), do: false

  @spec identity_key(t()) :: term()
  def identity_key(%__MODULE__{callback_topology: :dynamic_per_install, install_id: install_id}) do
    {:dynamic_per_install, install_id}
  end

  def identity_key(%__MODULE__{} = route) do
    {:static_per_app, route.connector_id, route.tenant_id, route.connection_id, route.install_id,
     route.trigger_id, route.tenant_resolution}
  end

  defp validate_route!(%__MODULE__{callback_topology: :dynamic_per_install, install_id: nil}) do
    raise ArgumentError, "install_id is required for dynamic_per_install routes"
  end

  defp validate_route!(%__MODULE__{callback_topology: :dynamic_per_install, tenant_id: nil}) do
    raise ArgumentError, "tenant_id is required for dynamic_per_install routes"
  end

  defp validate_route!(%__MODULE__{} = route), do: route

  defp normalize_topology(:dynamic_per_install), do: :dynamic_per_install
  defp normalize_topology(:static_per_app), do: :static_per_app
  defp normalize_topology("dynamic_per_install"), do: :dynamic_per_install
  defp normalize_topology("static_per_app"), do: :static_per_app

  defp normalize_topology(value) do
    raise ArgumentError,
          "callback_topology must be :dynamic_per_install or :static_per_app, got: #{inspect(value)}"
  end

  defp normalize_status(:active), do: :active
  defp normalize_status(:disabled), do: :disabled
  defp normalize_status(:revoked), do: :revoked
  defp normalize_status("active"), do: :active
  defp normalize_status("disabled"), do: :disabled
  defp normalize_status("revoked"), do: :revoked

  defp normalize_status(value) do
    raise ArgumentError, "invalid route status: #{inspect(value)}"
  end

  defp normalize_validator(nil), do: nil

  defp normalize_validator({module, function}) when is_atom(module) and is_atom(function),
    do: {module, function}

  defp normalize_validator(value) do
    raise ArgumentError,
          "validator must be nil or {module, function}, got: #{inspect(value)}"
  end

  defp normalize_verification(nil), do: nil

  defp normalize_verification(verification) when is_map(verification) do
    verification = Map.new(verification)
    secret = Contracts.get(verification, :secret)
    secret_ref = Contracts.get(verification, :secret_ref)

    cond do
      is_binary(secret) and not is_nil(secret_ref) ->
        raise ArgumentError, "verification must include either :secret or :secret_ref, not both"

      is_binary(secret) ->
        %{
          algorithm: Contracts.get(verification, :algorithm, :sha256),
          signature_header:
            Contracts.validate_non_empty_string!(
              Contracts.fetch!(verification, :signature_header),
              "verification.signature_header"
            ),
          secret: secret
        }

      not is_nil(secret_ref) ->
        %{
          algorithm: Contracts.get(verification, :algorithm, :sha256),
          signature_header:
            Contracts.validate_non_empty_string!(
              Contracts.fetch!(verification, :signature_header),
              "verification.signature_header"
            ),
          secret_ref: normalize_secret_ref(secret_ref)
        }

      true ->
        raise ArgumentError, "verification requires :secret or :secret_ref"
    end
  end

  defp normalize_verification(value) do
    raise ArgumentError, "verification must be a map or nil, got: #{inspect(value)}"
  end

  defp normalize_secret_ref(%CredentialRef{} = credential_ref) do
    %{credential_ref: credential_ref, secret_key: "webhook_secret"}
  end

  defp normalize_secret_ref(secret_ref) when is_map(secret_ref) do
    credential_ref = Contracts.get(secret_ref, :credential_ref)

    unless match?(%CredentialRef{}, credential_ref) do
      raise ArgumentError,
            "secret_ref must include a CredentialRef and secret_key, got: #{inspect(secret_ref)}"
    end

    %{
      credential_ref: credential_ref,
      secret_key:
        Contracts.validate_non_empty_string!(
          Contracts.get(secret_ref, :secret_key, "webhook_secret"),
          "verification.secret_ref.secret_key"
        )
    }
  end

  defp normalize_secret_ref(value) do
    raise ArgumentError,
          "secret_ref must include a CredentialRef and secret_key, got: #{inspect(value)}"
  end

  defp normalize_optional_string(nil, _field_name), do: nil
  defp normalize_optional_string("", _field_name), do: nil

  defp normalize_optional_string(value, field_name) do
    Contracts.validate_non_empty_string!(value, field_name)
  end

  defp normalize_resolution_keys(keys) when is_list(keys) do
    Enum.map(keys, &Contracts.validate_non_empty_string!(to_string(&1), "tenant_resolution_keys"))
  end

  defp normalize_resolution_keys(value) do
    raise ArgumentError, "tenant_resolution_keys must be a list, got: #{inspect(value)}"
  end

  defp normalize_resolution_map(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {Contracts.validate_non_empty_string!(to_string(key), "tenant_resolution"), value}
    end)
  end

  defp normalize_resolution_map(value) do
    raise ArgumentError, "tenant_resolution must be a map, got: #{inspect(value)}"
  end

  defp normalize_headers(headers) when is_list(headers) do
    Enum.map(headers, fn header ->
      header
      |> to_string()
      |> String.downcase()
      |> Contracts.validate_non_empty_string!("delivery_id_headers")
    end)
  end

  defp normalize_headers(value) do
    raise ArgumentError, "delivery_id_headers must be a list, got: #{inspect(value)}"
  end

  defp normalize_ttl(value) when is_integer(value) and value > 0, do: value

  defp normalize_ttl(value) do
    raise ArgumentError, "dedupe_ttl_seconds must be a positive integer, got: #{inspect(value)}"
  end

  defp normalize_revision(value) when is_integer(value) and value > 0, do: value

  defp normalize_revision(value) do
    raise ArgumentError, "revision must be a positive integer, got: #{inspect(value)}"
  end
end
