defmodule Jido.Integration.V2.StorePostgres.Repo do
  use Ecto.Repo,
    otp_app: :jido_integration_v2_store_postgres,
    adapter: Ecto.Adapters.Postgres
end
