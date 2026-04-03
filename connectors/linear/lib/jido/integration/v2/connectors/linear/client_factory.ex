defmodule Jido.Integration.V2.Connectors.Linear.ClientFactory do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Contracts

  @config_key __MODULE__
  @allowed_option_keys [
    :base_url,
    :headers,
    :oauth2,
    :req_options,
    :telemetry_prefix,
    :transport
  ]

  @spec build(map()) :: {:ok, LinearSDK.Client.t()} | {:error, :missing_runtime_auth}
  def build(context) when is_map(context) do
    with {:ok, auth_opts} <- runtime_auth(context) do
      opts =
        configured_opts()
        |> Keyword.merge(runtime_opts(context))
        |> Keyword.merge(auth_opts)

      LinearSDK.Client.new(opts)
    end
  end

  @spec auth_binding(map()) :: String.t()
  def auth_binding(context) when is_map(context) do
    context
    |> runtime_secret()
    |> ArtifactBuilder.digest()
  end

  defp configured_opts do
    :jido_integration_v2_linear
    |> Application.get_env(@config_key, [])
    |> Keyword.take(@allowed_option_keys)
  end

  defp runtime_opts(context) do
    context
    |> Map.get(:opts, %{})
    |> Contracts.get(:linear_client, [])
    |> normalize_runtime_opts()
    |> Keyword.take(@allowed_option_keys)
  end

  defp runtime_auth(context) do
    case runtime_auth_token(runtime_payload(context)) do
      {:access_token, access_token} -> {:ok, [access_token: access_token]}
      {:api_key, api_key} -> {:ok, [api_key: api_key]}
      :error -> {:error, :missing_runtime_auth}
    end
  end

  defp runtime_secret(context) do
    payload = runtime_payload(context)

    Contracts.get(payload, :access_token) ||
      Contracts.get(payload, :api_key)
  end

  defp runtime_payload(%{credential_lease: %{payload: payload}}) when is_map(payload), do: payload
  defp runtime_payload(_context), do: %{}

  defp runtime_auth_token(payload) do
    cond do
      value = present_secret(payload, :access_token) -> {:access_token, value}
      value = present_secret(payload, :api_key) -> {:api_key, value}
      true -> :error
    end
  end

  defp present_secret(payload, key) do
    case Contracts.get(payload, key) do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end

  defp normalize_runtime_opts(opts) when is_list(opts), do: opts
  defp normalize_runtime_opts(opts) when is_map(opts), do: Enum.into(opts, [])
  defp normalize_runtime_opts(_opts), do: []
end
