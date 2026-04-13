defmodule Jido.Integration.V2.Connectors.Linear.InstallBinding do
  @moduledoc false

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.Connectors.Linear
  alias Prismatic.OAuth2.Token

  @type t :: %{
          profile_id: String.t(),
          secret: map(),
          lease_fields: [String.t()],
          metadata: map(),
          expires_at: DateTime.t() | nil
        }

  @spec from_api_key(String.t()) :: t()
  def from_api_key(api_key) when is_binary(api_key) do
    trimmed = String.trim(api_key)

    if trimmed == "" do
      raise ArgumentError, "Linear API key must not be empty"
    end

    build_binding("api_key_user", %{api_key: trimmed}, nil)
  end

  @spec from_oauth_token(Token.t() | map()) :: t()
  def from_oauth_token(%Token{} = token) do
    secret =
      %{
        access_token: token.access_token,
        refresh_token: token.refresh_token
      }
      |> drop_nil_values()

    build_binding("oauth_user", secret, expires_at(token.expires_at))
  end

  def from_oauth_token(token) when is_map(token) do
    token
    |> Token.from_map()
    |> from_oauth_token()
  end

  @spec complete_install_attrs(String.t(), [String.t()], t(), keyword()) :: map()
  def complete_install_attrs(subject, granted_scopes, binding, opts \\ [])
      when is_binary(subject) and is_list(granted_scopes) and is_map(binding) and is_list(opts) do
    %{
      subject: subject,
      granted_scopes: granted_scopes,
      secret: Map.fetch!(binding, :secret),
      lease_fields: Map.fetch!(binding, :lease_fields),
      metadata: Map.fetch!(binding, :metadata),
      expires_at: Map.fetch!(binding, :expires_at)
    }
    |> maybe_put(:now, Keyword.get(opts, :now))
  end

  defp build_binding(profile_id, secret, expires_at) do
    profile = auth_profile(profile_id)

    %{
      profile_id: profile.id,
      secret: secret,
      lease_fields: profile.lease_fields,
      metadata: Map.put(profile.metadata, :profile_id, profile.id),
      expires_at: expires_at
    }
  end

  defp auth_profile(profile_id) do
    Linear.manifest().auth
    |> AuthSpec.fetch_profile(profile_id)
    |> case do
      nil ->
        raise "Linear auth profile #{inspect(profile_id)} is required for install binding"

      profile ->
        profile
    end
  end

  defp expires_at(nil), do: nil
  defp expires_at(value) when is_integer(value), do: DateTime.from_unix!(value)
  defp expires_at(%DateTime{} = value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end
end
