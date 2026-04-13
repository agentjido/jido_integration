import Config

if config_env() == :test do
  db_port =
    case Integer.parse(System.get_env("JIDO_INTEGRATION_V2_DB_PORT", "5432")) do
      {value, ""} -> value
      _ -> 5432
    end

  db_pool_size =
    case Integer.parse(System.get_env("JIDO_INTEGRATION_V2_DB_POOL_SIZE", "10")) do
      {value, ""} -> value
      _ -> 10
    end

  db_socket_dir = System.get_env("JIDO_INTEGRATION_V2_DB_SOCKET_DIR")
  config :jido_integration_v2_store_postgres, ecto_repos: [Jido.Integration.V2.StorePostgres.Repo]

  config :jido_integration_v2_store_postgres, Jido.Integration.V2.StorePostgres.Repo,
    username: System.get_env("JIDO_INTEGRATION_V2_DB_USER", "postgres"),
    password: System.get_env("JIDO_INTEGRATION_V2_DB_PASSWORD", "postgres"),
    database: System.get_env("JIDO_INTEGRATION_V2_DB_NAME", "jido_integration_v2_test"),
    pool: DBConnection.ConnectionPool,
    pool_size: db_pool_size,
    queue_target: 5000,
    queue_interval: 1000,
    timeout: 15000

  if db_socket_dir in [nil, ""] do
    config :jido_integration_v2_store_postgres, Jido.Integration.V2.StorePostgres.Repo,
      hostname: System.get_env("JIDO_INTEGRATION_V2_DB_HOST", "127.0.0.1"),
      port: db_port
  else
    config :jido_integration_v2_store_postgres, Jido.Integration.V2.StorePostgres.Repo,
      socket_dir: db_socket_dir,
      port: db_port
  end
end
