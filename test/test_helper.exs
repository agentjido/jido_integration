ExUnit.start()

Code.require_file("support/connector_contract_case.exs", __DIR__)

Jido.Integration.V2.StorePostgres.TestSupport.configure_defaults!()
Jido.Integration.V2.StorePostgres.TestSupport.setup_database!()
Ecto.Adapters.SQL.Sandbox.mode(Jido.Integration.V2.StorePostgres.Repo, :auto)

{:ok, _} = Application.ensure_all_started(:jido_integration_v2)
