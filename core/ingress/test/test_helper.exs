ExUnit.start()

alias Jido.Integration.V2.StorePostgres.TestSupport

TestSupport.setup_database!(pool: DBConnection.ConnectionPool)
