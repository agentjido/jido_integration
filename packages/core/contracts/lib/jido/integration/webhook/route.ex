defmodule Jido.Integration.Webhook.Route do
  @moduledoc """
  Normalized webhook route binding.

  Route bindings capture the connector, tenant, connection, verification, and
  dispatch metadata needed to resolve and process inbound webhook traffic.
  """

  @type callback_topology :: :dynamic_per_install | :static_per_app
  @type status :: :active | :disabled | :revoked

  @type t :: %__MODULE__{
          connector_id: String.t(),
          tenant_id: String.t() | nil,
          connection_id: String.t() | nil,
          install_id: String.t() | nil,
          trigger_id: String.t() | nil,
          path_pattern: String.t() | nil,
          callback_topology: callback_topology(),
          tenant_resolution_key: String.t() | nil,
          tenant_resolution_keys: [String.t()],
          tenant_resolution: map(),
          delivery_id_headers: [String.t()],
          verification: map(),
          replay_window_days: pos_integer(),
          status: status(),
          revision: non_neg_integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @enforce_keys [:connector_id, :callback_topology]
  defstruct [
    :connector_id,
    :tenant_id,
    :connection_id,
    :install_id,
    :trigger_id,
    :path_pattern,
    :tenant_resolution_key,
    callback_topology: :dynamic_per_install,
    tenant_resolution_keys: [],
    tenant_resolution: %{},
    delivery_id_headers: [],
    verification: %{},
    replay_window_days: 7,
    status: :active,
    revision: 1,
    inserted_at: nil,
    updated_at: nil
  ]

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_list(attrs), do: attrs |> Enum.into(%{}) |> new()

  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()
    connector_id = fetch(attrs, :connector_id)
    callback_topology = normalize_topology(fetch(attrs, :callback_topology))

    cond do
      not is_binary(connector_id) or connector_id == "" ->
        {:error, "connector_id is required"}

      is_nil(callback_topology) ->
        {:error, "callback_topology is required"}

      true ->
        tenant_resolution_keys =
          attrs
          |> fetch(:tenant_resolution_keys, [])
          |> normalize_resolution_keys(fetch(attrs, :tenant_resolution_key))

        route =
          %__MODULE__{
            connector_id: connector_id,
            tenant_id: fetch(attrs, :tenant_id),
            connection_id: fetch(attrs, :connection_id),
            install_id: fetch(attrs, :install_id),
            trigger_id: fetch(attrs, :trigger_id),
            path_pattern: fetch(attrs, :path_pattern),
            callback_topology: callback_topology,
            tenant_resolution_key: List.first(tenant_resolution_keys),
            tenant_resolution_keys: tenant_resolution_keys,
            tenant_resolution: fetch(attrs, :tenant_resolution, %{}),
            delivery_id_headers: normalize_headers(fetch(attrs, :delivery_id_headers, [])),
            verification: normalize_verification(fetch(attrs, :verification, %{})),
            replay_window_days: fetch(attrs, :replay_window_days, 7),
            status: normalize_status(fetch(attrs, :status, :active)),
            revision: fetch(attrs, :revision, 1),
            inserted_at: fetch(attrs, :inserted_at, now),
            updated_at: fetch(attrs, :updated_at, now)
          }

        {:ok, route}
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, route} -> route
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{status: :active}), do: true
  def active?(%__MODULE__{}), do: false

  defp fetch(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp normalize_topology(:dynamic_per_install), do: :dynamic_per_install
  defp normalize_topology(:static_per_app), do: :static_per_app
  defp normalize_topology("dynamic_per_install"), do: :dynamic_per_install
  defp normalize_topology("static_per_app"), do: :static_per_app
  defp normalize_topology(_), do: nil

  defp normalize_status(:active), do: :active
  defp normalize_status(:disabled), do: :disabled
  defp normalize_status(:revoked), do: :revoked
  defp normalize_status("active"), do: :active
  defp normalize_status("disabled"), do: :disabled
  defp normalize_status("revoked"), do: :revoked
  defp normalize_status(_), do: :active

  defp normalize_resolution_keys([], nil), do: []
  defp normalize_resolution_keys([], key) when is_binary(key), do: [key]
  defp normalize_resolution_keys(keys, _key) when is_list(keys), do: Enum.map(keys, &to_string/1)

  defp normalize_headers([]), do: []

  defp normalize_headers(headers) when is_list(headers),
    do: Enum.map(headers, &String.downcase(to_string(&1)))

  defp normalize_verification(verification) when is_map(verification) do
    Map.new(verification, fn {key, value} ->
      normalized_key = normalize_verification_key(key)

      normalized_value =
        case {normalized_key, value} do
          {:header, header} -> String.downcase(to_string(header))
          {:algorithm, "sha256"} -> :sha256
          {:algorithm, "sha1"} -> :sha1
          _ -> value
        end

      {normalized_key, normalized_value}
    end)
  end

  defp normalize_verification_key(key) when key in [:type, :algorithm, :header, :secret_ref],
    do: key

  defp normalize_verification_key("type"), do: :type
  defp normalize_verification_key("algorithm"), do: :algorithm
  defp normalize_verification_key("header"), do: :header
  defp normalize_verification_key("secret_ref"), do: :secret_ref
  defp normalize_verification_key(key) when is_binary(key), do: key
  defp normalize_verification_key(key), do: key
end
