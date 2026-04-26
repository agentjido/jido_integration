import Config

config :jido_integration_v2_store_postgres,
  ecto_repos: [Jido.Integration.V2.StorePostgres.Repo]

config :jido_integration_v2_store_postgres, Jido.Integration.V2.StorePostgres.Repo,
  username: "postgres",
  password: "postgres",
  database: "jido_integration_v2_test",
  hostname: "127.0.0.1",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  queue_target: 5_000,
  queue_interval: 1_000,
  timeout: 15_000,
  ownership_timeout: 60_000
