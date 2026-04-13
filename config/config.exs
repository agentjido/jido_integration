import Config

import_config "sources/core_ingress/config.exs"
import_config "sources/core_platform/config.exs"
import_config "sources/core_runtime_control/config.exs"
import_config "sources/core_store_postgres/config.exs"

config :jido_integration,
  ecto_repos: [Jido.Integration.V2.StorePostgres.Repo]
