defmodule Jido.Integration.V2.Connectors.GitHub.LiveEnv do
  @moduledoc false

  @type mode :: :auth | :read | :write

  @env_names %{
    live: "JIDO_INTEGRATION_V2_GITHUB_LIVE",
    live_write: "JIDO_INTEGRATION_V2_GITHUB_LIVE_WRITE",
    repo: "JIDO_INTEGRATION_V2_GITHUB_REPO",
    write_repo: "JIDO_INTEGRATION_V2_GITHUB_WRITE_REPO",
    read_issue_number: "JIDO_INTEGRATION_V2_GITHUB_READ_ISSUE_NUMBER",
    token: "JIDO_INTEGRATION_V2_GITHUB_TOKEN",
    fallback_token: "GITHUB_TOKEN",
    subject: "JIDO_INTEGRATION_V2_GITHUB_SUBJECT",
    actor_id: "JIDO_INTEGRATION_V2_GITHUB_ACTOR_ID",
    tenant_id: "JIDO_INTEGRATION_V2_GITHUB_TENANT_ID",
    write_label: "JIDO_INTEGRATION_V2_GITHUB_WRITE_LABEL",
    api_base_url: "JIDO_INTEGRATION_V2_GITHUB_API_BASE_URL",
    timeout_ms: "JIDO_INTEGRATION_V2_GITHUB_TIMEOUT_MS"
  }

  @defaults %{
    subject: "github-live-proof",
    actor_id: "github-live-proof",
    tenant_id: "tenant-github-live",
    write_label: "jido-live-acceptance"
  }

  @spec env_names() :: map()
  def env_names, do: @env_names

  @spec preferred_token_envs() :: [String.t()]
  def preferred_token_envs do
    [@env_names.token, @env_names.fallback_token]
  end

  @spec spec(map()) :: map()
  def spec(env \\ System.get_env()) when is_map(env) do
    read_enabled? = enabled?(Map.get(env, @env_names.live))
    repo = normalize_repo(Map.get(env, @env_names.repo))

    %{
      read_enabled?: read_enabled?,
      write_enabled?: read_enabled? and enabled?(Map.get(env, @env_names.live_write)),
      repo: repo,
      write_repo: normalize_repo(Map.get(env, @env_names.write_repo)) || repo,
      read_issue_number: parse_positive_integer(Map.get(env, @env_names.read_issue_number)),
      token: token_from_env(env),
      subject: present_or_default(Map.get(env, @env_names.subject), @defaults.subject),
      actor_id: present_or_default(Map.get(env, @env_names.actor_id), @defaults.actor_id),
      tenant_id: present_or_default(Map.get(env, @env_names.tenant_id), @defaults.tenant_id),
      write_label:
        present_or_default(Map.get(env, @env_names.write_label), @defaults.write_label),
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

  defp missing_requirements(spec, mode) do
    []
    |> maybe_require(not spec.read_enabled?, @env_names.live)
    |> maybe_require(mode == :write and not spec.write_enabled?, @env_names.live_write)
    |> maybe_require(mode in [:read, :write] and is_nil(spec.repo), @env_names.repo)
  end

  defp maybe_require(missing, true, env_name), do: missing ++ [env_name]
  defp maybe_require(missing, false, _env_name), do: missing

  defp token_from_env(env) do
    Enum.find_value(preferred_token_envs(), fn env_name ->
      present_or_nil(Map.get(env, env_name))
    end)
  end

  defp enabled?(value), do: value in ["1", "true", "TRUE", "yes", "YES", "on", "ON"]

  defp normalize_repo(value) do
    value = present_or_nil(value)

    case value && String.split(value, "/", parts: 2) do
      [owner, repo] when owner != "" and repo != "" -> value
      _other -> nil
    end
  end

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
