ExUnit.start()

Code.require_file("support/fixtures.ex", __DIR__)
Code.require_file("support/data_case.ex", __DIR__)

Jido.Integration.V2.StorePostgres.TestSupport.setup_database!()
