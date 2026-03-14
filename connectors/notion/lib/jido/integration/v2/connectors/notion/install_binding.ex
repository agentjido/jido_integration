defmodule Jido.Integration.V2.Connectors.Notion.InstallBinding do
  @moduledoc false

  alias Pristine.OAuth2.Token

  @metadata_keys ~w(workspace_id workspace_name bot_id)

  @type t :: %{
          secret: map(),
          lease_fields: [String.t()],
          metadata: map(),
          expires_at: DateTime.t() | nil
        }

  @spec from_token(Token.t() | map()) :: t()
  def from_token(%Token{} = token) do
    secret =
      %{
        access_token: token.access_token,
        refresh_token: token.refresh_token
      }
      |> merge_metadata(token.other_params)
      |> drop_nil_values()

    %{
      secret: secret,
      lease_fields: lease_fields(secret),
      metadata: metadata(secret),
      expires_at: expires_at(token.expires_at)
    }
  end

  def from_token(token) when is_map(token) do
    token
    |> Token.from_map()
    |> from_token()
  end

  @spec from_live_spec(map()) :: t()
  def from_live_spec(spec) when is_map(spec) do
    secret =
      %{
        access_token: Map.get(spec, :access_token),
        refresh_token: Map.get(spec, :refresh_token),
        workspace_id: Map.get(spec, :workspace_id),
        workspace_name: Map.get(spec, :workspace_name),
        bot_id: Map.get(spec, :bot_id)
      }
      |> drop_nil_values()

    %{
      secret: secret,
      lease_fields: lease_fields(secret),
      metadata: metadata(secret),
      expires_at: nil
    }
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

  defp merge_metadata(secret, other_params) when is_map(other_params) do
    Enum.reduce(@metadata_keys, secret, fn key, acc ->
      case Map.get(other_params, key) do
        value when is_binary(value) and value != "" ->
          Map.put(acc, String.to_atom(key), value)

        _other ->
          acc
      end
    end)
  end

  defp merge_metadata(secret, _other_params), do: secret

  defp metadata(secret) do
    Enum.reduce(@metadata_keys, %{}, fn key, acc ->
      atom_key = String.to_atom(key)

      case Map.get(secret, atom_key) do
        value when is_binary(value) and value != "" -> Map.put(acc, atom_key, value)
        _other -> acc
      end
    end)
  end

  defp lease_fields(secret) do
    ["access_token" | @metadata_keys]
    |> Enum.filter(fn key ->
      Map.has_key?(secret, String.to_atom(key)) or Map.has_key?(secret, key)
    end)
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
