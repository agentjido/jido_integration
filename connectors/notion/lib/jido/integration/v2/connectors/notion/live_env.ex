defmodule Jido.Integration.V2.Connectors.Notion.LiveEnv do
  @moduledoc false

  @type mode :: :auth | :read | :write

  @env_names %{
    live: "JIDO_INTEGRATION_V2_NOTION_LIVE",
    live_write: "JIDO_INTEGRATION_V2_NOTION_LIVE_WRITE",
    client_id: "JIDO_INTEGRATION_V2_NOTION_CLIENT_ID",
    client_secret: "JIDO_INTEGRATION_V2_NOTION_CLIENT_SECRET",
    redirect_uri: "JIDO_INTEGRATION_V2_NOTION_REDIRECT_URI",
    auth_code: "JIDO_INTEGRATION_V2_NOTION_AUTH_CODE",
    callback_url: "JIDO_INTEGRATION_V2_NOTION_CALLBACK_URL",
    access_token: "JIDO_INTEGRATION_V2_NOTION_ACCESS_TOKEN",
    refresh_token: "JIDO_INTEGRATION_V2_NOTION_REFRESH_TOKEN",
    read_page_id: "JIDO_INTEGRATION_V2_NOTION_READ_PAGE_ID",
    write_parent_data_source_id: "JIDO_INTEGRATION_V2_NOTION_WRITE_PARENT_DATA_SOURCE_ID",
    write_title_property: "JIDO_INTEGRATION_V2_NOTION_WRITE_TITLE_PROPERTY",
    workspace_id: "JIDO_INTEGRATION_V2_NOTION_WORKSPACE_ID",
    workspace_name: "JIDO_INTEGRATION_V2_NOTION_WORKSPACE_NAME",
    bot_id: "JIDO_INTEGRATION_V2_NOTION_BOT_ID",
    subject: "JIDO_INTEGRATION_V2_NOTION_SUBJECT",
    actor_id: "JIDO_INTEGRATION_V2_NOTION_ACTOR_ID",
    tenant_id: "JIDO_INTEGRATION_V2_NOTION_TENANT_ID",
    write_page_title: "JIDO_INTEGRATION_V2_NOTION_WRITE_PAGE_TITLE",
    api_base_url: "JIDO_INTEGRATION_V2_NOTION_API_BASE_URL",
    timeout_ms: "JIDO_INTEGRATION_V2_NOTION_TIMEOUT_MS"
  }

  @defaults %{
    subject: "notion-live-proof",
    actor_id: "notion-live-proof",
    tenant_id: "tenant-notion-live",
    write_title_property: "Name",
    write_page_title: "Jido live acceptance page"
  }

  @spec env_names() :: map()
  def env_names, do: @env_names

  @spec spec(map()) :: map()
  def spec(env \\ System.get_env()) when is_map(env) do
    live_enabled? = enabled?(Map.get(env, @env_names.live))

    %{
      live_enabled?: live_enabled?,
      write_enabled?: live_enabled? and enabled?(Map.get(env, @env_names.live_write)),
      client_id: present_or_nil(Map.get(env, @env_names.client_id)),
      client_secret: present_or_nil(Map.get(env, @env_names.client_secret)),
      redirect_uri: present_or_nil(Map.get(env, @env_names.redirect_uri)),
      auth_code: present_or_nil(Map.get(env, @env_names.auth_code)),
      callback_url: present_or_nil(Map.get(env, @env_names.callback_url)),
      access_token: present_or_nil(Map.get(env, @env_names.access_token)),
      refresh_token: present_or_nil(Map.get(env, @env_names.refresh_token)),
      read_page_id: present_or_nil(Map.get(env, @env_names.read_page_id)),
      write_parent_data_source_id:
        present_or_nil(Map.get(env, @env_names.write_parent_data_source_id)),
      write_title_property:
        present_or_default(
          Map.get(env, @env_names.write_title_property),
          @defaults.write_title_property
        ),
      workspace_id: present_or_nil(Map.get(env, @env_names.workspace_id)),
      workspace_name: present_or_nil(Map.get(env, @env_names.workspace_name)),
      bot_id: present_or_nil(Map.get(env, @env_names.bot_id)),
      subject: present_or_default(Map.get(env, @env_names.subject), @defaults.subject),
      actor_id: present_or_default(Map.get(env, @env_names.actor_id), @defaults.actor_id),
      tenant_id: present_or_default(Map.get(env, @env_names.tenant_id), @defaults.tenant_id),
      write_page_title:
        present_or_default(Map.get(env, @env_names.write_page_title), @defaults.write_page_title),
      api_base_url: present_or_nil(Map.get(env, @env_names.api_base_url)),
      timeout_ms: parse_positive_integer(Map.get(env, @env_names.timeout_ms))
    }
  end

  @spec validate(mode(), map()) :: :ok | {:error, [String.t()]}
  def validate(mode, env \\ System.get_env())

  def validate(mode, env) when mode in [:auth, :read, :write] and is_map(env) do
    env
    |> spec()
    |> missing_requirements(mode)
    |> case do
      [] -> :ok
      missing -> {:error, missing}
    end
  end

  defp missing_requirements(spec, :auth) do
    []
    |> maybe_require(not spec.live_enabled?, @env_names.live)
    |> maybe_require(is_nil(spec.client_id), @env_names.client_id)
    |> maybe_require(is_nil(spec.client_secret), @env_names.client_secret)
    |> maybe_require(is_nil(spec.redirect_uri), @env_names.redirect_uri)
  end

  defp missing_requirements(spec, :read) do
    []
    |> maybe_require(not spec.live_enabled?, @env_names.live)
    |> maybe_require(is_nil(spec.access_token), @env_names.access_token)
    |> maybe_require(is_nil(spec.read_page_id), @env_names.read_page_id)
  end

  defp missing_requirements(spec, :write) do
    []
    |> maybe_require(not spec.live_enabled?, @env_names.live)
    |> maybe_require(not spec.write_enabled?, @env_names.live_write)
    |> maybe_require(is_nil(spec.access_token), @env_names.access_token)
    |> maybe_require(
      is_nil(spec.write_parent_data_source_id),
      @env_names.write_parent_data_source_id
    )
  end

  defp maybe_require(missing, true, env_name), do: missing ++ [env_name]
  defp maybe_require(missing, false, _env_name), do: missing

  defp enabled?(value), do: value in ["1", "true", "TRUE", "yes", "YES", "on", "ON"]

  defp parse_positive_integer(value) do
    case Integer.parse(to_string(value || "")) do
      {parsed, ""} when parsed > 0 -> parsed
      _other -> nil
    end
  end

  defp present_or_default(value, default), do: present_or_nil(value) || default

  defp present_or_nil(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      present -> present
    end
  end

  defp present_or_nil(_value), do: nil
end
