defmodule Jido.Integration.V2.Connectors.Linear.GeneratedConsumerSurfaceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2, as: V2
  alias Jido.Integration.V2.Connectors.Linear
  alias Jido.Integration.V2.Connectors.Linear.Fixtures
  alias Jido.Integration.V2.Connectors.Linear.Generated.Actions.UsersGetSelf
  alias Jido.Integration.V2.Connectors.Linear.Generated.Plugin, as: GeneratedPlugin
  alias Jido.Integration.V2.Connectors.Linear.InstallBinding
  alias Jido.Integration.V2.ConsumerProjection
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.InvocationRequest

  setup do
    V2.reset!()
    :ok
  end

  test "compiles one generated action module per published operation with static metadata" do
    manifest = Linear.manifest()
    projected_operations = ConsumerProjection.projected_operations(manifest)

    assert Enum.map(projected_operations, & &1.operation_id) ==
             Enum.map(manifest.operations, & &1.operation_id)

    Enum.each(projected_operations, fn operation ->
      action_module = ConsumerProjection.action_module(Linear, operation.operation_id)

      assert Code.ensure_loaded?(action_module)
      assert function_exported?(action_module, :run, 2)
      assert function_exported?(action_module, :schema, 0)
      assert function_exported?(action_module, :output_schema, 0)
      assert action_module.operation_id() == operation.operation_id
      assert action_module.name() == operation.jido.action.name
      assert action_module.description() == operation.description
      assert action_module.category() == manifest.catalog.category
      assert action_module.schema() == operation.input_schema
      assert action_module.output_schema() == operation.output_schema
    end)
  end

  test "generated actions invoke the public facade with typed request bindings from params or plugin config" do
    projection = UsersGetSelf.generated_action_projection()

    assert {:ok, _parsed_input} =
             Zoi.parse(UsersGetSelf.schema(), %{})

    assert %InvocationRequest{
             capability_id: "linear.users.get_self",
             connection_id: "conn-param",
             input: %{},
             trace_id: "trace-generated-linear"
           } =
             ConsumerProjection.invocation_request!(
               projection,
               %{connection_id: "conn-param"},
               %{trace_id: "trace-generated-linear"}
             )

    assert %InvocationRequest{
             capability_id: "linear.users.get_self",
             connection_id: "conn-plugin",
             input: %{}
           } =
             ConsumerProjection.invocation_request!(
               projection,
               %{},
               %{plugin_config: %{connection_id: "conn-plugin"}}
             )
  end

  test "generated actions execute the full Linear A0 slice through the real direct facade" do
    register_connector!()
    connection_id = install_connection!()

    Enum.each(Fixtures.specs(), fn spec ->
      capability = fetch_capability!(spec.capability_id)
      action_module = ConsumerProjection.action_module(Linear, spec.capability_id)

      assert {:ok, output} =
               action_module.run(
                 Map.put(spec.input, :connection_id, connection_id),
                 %{
                   invoke: %{
                     actor_id: "generated-consumer",
                     tenant_id: "tenant-generated-linear",
                     environment: :prod,
                     trace_id: "trace-#{String.replace(spec.capability_id, ".", "-")}",
                     allowed_operations: [spec.capability_id],
                     sandbox: capability.metadata.policy.sandbox,
                     extensions: [
                       linear_client: Fixtures.client_opts(),
                       linear_request: Fixtures.request_opts(self())
                     ]
                   }
                 }
               )

      assert output == spec.output

      assert_receive {:transport_request, payload, context, _opts}
      Fixtures.assert_request(spec.capability_id, payload, context)
    end)
  end

  test "generated plugin exposes the real Jido.Plugin contract over the generated action bundle only" do
    manifest = Linear.manifest()
    plugin = GeneratedPlugin
    projected_operations = ConsumerProjection.projected_operations(manifest)

    expected_actions =
      Enum.map(projected_operations, fn operation ->
        ConsumerProjection.action_module(Linear, operation.operation_id)
      end)

    assert Code.ensure_loaded?(plugin)
    assert plugin.name() == "linear"
    assert plugin.state_key() == :linear
    assert plugin.actions() == expected_actions
    assert plugin.subscriptions() == []

    assert plugin.subscriptions(%{connection_id: "conn-linear"}, %{agent_id: "agent-linear"}) ==
             []

    assert {:ok, parsed_config} =
             Zoi.parse(
               plugin.config_schema(),
               %{connection_id: "conn-linear", enabled_actions: ["users_get_self"]}
             )

    assert parsed_config.connection_id == "conn-linear"
    assert parsed_config.enabled_actions == ["users_get_self"]

    assert plugin.manifest().actions == expected_actions
    assert plugin.manifest().subscriptions == []
    assert plugin.plugin_spec(%{connection_id: "conn-linear"}).actions == expected_actions

    assert plugin.plugin_spec(%{
             connection_id: "conn-linear",
             enabled_actions: ["users_get_self"]
           }).actions == [UsersGetSelf]

    refute Enum.any?(
             Linear.manifest().operations,
             &String.contains?(&1.operation_id, "install_binding")
           )
  end

  defp register_connector! do
    assert :ok = V2.register_connector(Linear)
  end

  defp install_connection! do
    now = Contracts.now()
    auth = Linear.manifest().auth
    binding = InstallBinding.from_api_key(Fixtures.api_key())

    assert {:ok, %{install: install, connection: connection}} =
             V2.start_install("linear", "tenant-generated-linear", %{
               actor_id: "generated-consumer",
               auth_type: auth.auth_type,
               profile_id: auth.default_profile,
               subject: "usr-linear-viewer",
               requested_scopes: auth.requested_scopes,
               now: now
             })

    assert {:ok,
            %{install: %{install_id: install_id}, connection: %{connection_id: connection_id}}} =
             V2.complete_install(
               install.install_id,
               InstallBinding.complete_install_attrs(
                 "usr-linear-viewer",
                 auth.requested_scopes,
                 %{binding | expires_at: DateTime.add(now, 7 * 24 * 3_600, :second)},
                 now: now
               )
             )

    assert install_id == install.install_id
    assert connection_id == connection.connection_id
    connection_id
  end

  defp fetch_capability!(capability_id) do
    Enum.find(Linear.manifest().capabilities, &(&1.id == capability_id)) ||
      raise "missing capability #{capability_id}"
  end

end
