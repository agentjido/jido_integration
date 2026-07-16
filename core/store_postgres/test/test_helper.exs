ExUnit.start()

{:ok, capability} = Jido.Integration.V2.StorePostgres.store_capability()

{:ok, _runtime} =
  Supervisor.start_link(
    [
      {Jido.Integration.V2.Auth.Persistence.Owner,
       profile: :integration_postgres,
       capabilities: [capability],
       store_modules: Jido.Integration.V2.StorePostgres.auth_store_modules()},
      {Jido.Integration.V2.Auth.RuntimeConfig, []},
      {Task.Supervisor, name: Jido.Integration.V2.Auth.MaterializationSupervisor},
      {Jido.Integration.V2.ControlPlane.Persistence.Owner,
       profile: :integration_postgres,
       capabilities: [capability],
       store_modules: Jido.Integration.V2.StorePostgres.control_plane_store_modules()},
      {Jido.Integration.V2.ControlPlane.RuntimeConfig, []},
      {Jido.Integration.V2.ControlPlane.Registry, []}
    ],
    strategy: :rest_for_one,
    name: Jido.Integration.V2.StorePostgres.TestRuntime
  )

Code.require_file("support/fixtures_helper.exs", __DIR__)
Code.require_file("support/data_case_helper.exs", __DIR__)
