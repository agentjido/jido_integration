defmodule Jido.Integration.Workspace.PostgresPreflight do
  @moduledoc false

  @default_database "jido_integration_v2_test"
  @default_host "127.0.0.1"
  @default_port 5432
  @default_timeout_ms 1_000
  @default_user "postgres"

  @enforce_keys [:database, :host, :port, :timeout_ms, :user]
  defstruct [:database, :host, :socket_dir, :port, :timeout_ms, :user]

  @type t :: %__MODULE__{
          database: String.t(),
          host: String.t(),
          socket_dir: String.t() | nil,
          port: pos_integer(),
          timeout_ms: pos_integer(),
          user: String.t()
        }

  @spec from_env(map()) :: t()
  def from_env(env \\ System.get_env()) when is_map(env) do
    %__MODULE__{
      database: Map.get(env, "JIDO_INTEGRATION_V2_DB_NAME", @default_database),
      host: Map.get(env, "JIDO_INTEGRATION_V2_DB_HOST", @default_host),
      socket_dir: normalize_blank(Map.get(env, "JIDO_INTEGRATION_V2_DB_SOCKET_DIR")),
      port: parse_integer(Map.get(env, "JIDO_INTEGRATION_V2_DB_PORT"), @default_port),
      timeout_ms:
        parse_integer(Map.get(env, "JIDO_INTEGRATION_V2_DB_TIMEOUT_MS"), @default_timeout_ms),
      user: Map.get(env, "JIDO_INTEGRATION_V2_DB_USER", @default_user)
    }
  end

  @spec pg_isready_args(t()) :: [String.t()]
  def pg_isready_args(%__MODULE__{} = config) do
    host_args =
      case config.socket_dir do
        nil -> ["-h", config.host]
        socket_dir -> ["-h", socket_dir]
      end

    host_args ++
      [
        "-p",
        Integer.to_string(config.port),
        "-d",
        config.database,
        "-U",
        config.user,
        "-t",
        timeout_seconds(config.timeout_ms)
      ]
  end

  @spec target_label(t()) :: String.t()
  def target_label(%__MODULE__{socket_dir: socket_dir, port: port})
      when is_binary(socket_dir) do
    Path.join(socket_dir, ".s.PGSQL.#{port}")
  end

  def target_label(%__MODULE__{host: host, port: port}) do
    "#{host}:#{port}"
  end

  defp normalize_blank(nil), do: nil
  defp normalize_blank(""), do: nil
  defp normalize_blank(value), do: value

  defp parse_integer(nil, fallback), do: fallback

  defp parse_integer(value, fallback) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> fallback
    end
  end

  defp timeout_seconds(timeout_ms) do
    timeout_ms
    |> Kernel.max(1)
    |> Kernel.+(999)
    |> div(1_000)
    |> Integer.to_string()
  end
end
