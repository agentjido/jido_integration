ExUnit.start()

Application.put_env(
  :jido_integration_v2_github,
  Jido.Integration.V2.Connectors.GitHub.ClientFactory,
  transport: Jido.Integration.V2.Connectors.GitHub.FixtureTransport
)

alias Jido.Integration.V2.StorePostgres.TestSupport

TestSupport.setup_database!(pool: DBConnection.ConnectionPool)
