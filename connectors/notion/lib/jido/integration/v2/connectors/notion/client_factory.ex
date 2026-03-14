defmodule Jido.Integration.V2.Connectors.Notion.ClientFactory do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Contracts

  @config_key __MODULE__
  @allowed_option_keys [
    :base_url,
    :foundation,
    :log_level,
    :logger,
    :notion_version,
    :retry,
    :timeout_ms,
    :transport,
    :transport_opts,
    :typed_responses,
    :user_agent
  ]

  @spec build(map()) :: {:ok, NotionSDK.Client.t()} | {:error, :missing_access_token}
  def build(context) when is_map(context) do
    case access_token(context) do
      nil ->
        {:error, :missing_access_token}

      access_token ->
        opts =
          configured_opts()
          |> Keyword.merge(runtime_opts(context))
          |> Keyword.put(:auth, access_token)
          |> Keyword.put(:typed_responses, false)

        {:ok, NotionSDK.Client.new(opts)}
    end
  end

  @spec auth_binding(map()) :: String.t()
  def auth_binding(context) when is_map(context) do
    context
    |> access_token()
    |> ArtifactBuilder.digest()
  end

  defp configured_opts do
    :jido_integration_v2_notion
    |> Application.get_env(@config_key, [])
    |> Keyword.take(@allowed_option_keys)
  end

  defp runtime_opts(context) do
    context
    |> Map.get(:opts, %{})
    |> Contracts.get(:notion_client, [])
    |> normalize_runtime_opts()
    |> Keyword.take(@allowed_option_keys)
  end

  defp normalize_runtime_opts(opts) when is_list(opts), do: opts
  defp normalize_runtime_opts(opts) when is_map(opts), do: Enum.into(opts, [])
  defp normalize_runtime_opts(_opts), do: []

  defp access_token(%{credential_lease: %{payload: payload}}) when is_map(payload) do
    Contracts.get(payload, :access_token)
  end

  defp access_token(_context), do: nil
end
