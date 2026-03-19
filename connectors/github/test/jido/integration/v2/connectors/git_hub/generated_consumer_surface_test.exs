defmodule Jido.Integration.V2.Connectors.GitHub.GeneratedConsumerSurfaceTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.GitHub.Generated.Actions.IssueFetch
  alias Jido.Integration.V2.Connectors.GitHub.Generated.Plugin, as: GeneratedPlugin
  alias Jido.Integration.V2.ConsumerProjection
  alias Jido.Integration.V2.InvocationRequest

  defmodule FakeInvoker do
    def invoke(request) do
      send(self(), {:generated_invoke, request})

      {:ok,
       %{
         run: %{run_id: "run-generated"},
         attempt: %{attempt_id: "run-generated:1"},
         output: %{request_capability_id: request.capability_id, echoed_input: request.input}
       }}
    end
  end

  test "compiles one generated action module per published operation with static metadata" do
    manifest = GitHub.manifest()

    Enum.each(manifest.operations, fn operation ->
      action_module = ConsumerProjection.action_module(GitHub, operation.operation_id)

      assert Code.ensure_loaded?(action_module)
      assert function_exported?(action_module, :run, 2)
      assert function_exported?(action_module, :schema, 0)
      assert action_module.operation_id() == operation.operation_id
      assert action_module.name() == operation.jido.action.name
      assert action_module.description() == operation.description
      assert action_module.category() == manifest.catalog.category
      assert action_module.schema() == operation.input_schema
      assert action_module.output_schema() == operation.output_schema
    end)
  end

  test "generated actions invoke the public request contract with connection_id from params or plugin config" do
    assert {:ok, %{request_capability_id: "github.issue.fetch"} = output} =
             IssueFetch.run(
               %{owner: "acme", repo: "widgets", issue_number: 7, connection_id: "conn-param"},
               %{invoker: FakeInvoker, trace_id: "trace-generated-1"}
             )

    assert output.echoed_input == %{owner: "acme", repo: "widgets", issue_number: 7}

    assert_receive {:generated_invoke,
                    %InvocationRequest{
                      capability_id: "github.issue.fetch",
                      connection_id: "conn-param",
                      input: %{owner: "acme", repo: "widgets", issue_number: 7},
                      trace_id: "trace-generated-1"
                    }}

    assert {:ok, %{request_capability_id: "github.issue.fetch"}} =
             IssueFetch.run(
               %{owner: "acme", repo: "widgets", issue_number: 8},
               %{invoker: FakeInvoker, plugin_config: %{connection_id: "conn-plugin"}}
             )

    assert_receive {:generated_invoke,
                    %InvocationRequest{
                      capability_id: "github.issue.fetch",
                      connection_id: "conn-plugin",
                      input: %{owner: "acme", repo: "widgets", issue_number: 8}
                    }}
  end

  test "generated plugin exposes the real Jido.Plugin contract over the generated action bundle" do
    manifest = GitHub.manifest()
    plugin = GeneratedPlugin

    expected_actions =
      Enum.map(manifest.operations, fn operation ->
        ConsumerProjection.action_module(GitHub, operation.operation_id)
      end)

    assert Code.ensure_loaded?(plugin)
    assert plugin.name() == "github"
    assert plugin.state_key() == :github
    assert plugin.actions() == expected_actions
    assert plugin.subscriptions() == []
    assert plugin.subscriptions(%{connection_id: "conn-gh"}, %{agent_id: "agent-gh"}) == []

    assert {:ok, parsed_config} =
             Zoi.parse(
               plugin.config_schema(),
               %{connection_id: "conn-gh", enabled_actions: ["github_issue_fetch"]}
             )

    assert parsed_config.connection_id == "conn-gh"
    assert parsed_config.enabled_actions == ["github_issue_fetch"]

    assert plugin.manifest().actions == expected_actions
    assert plugin.manifest().subscriptions == []
    assert plugin.plugin_spec(%{connection_id: "conn-gh"}).actions == expected_actions

    assert plugin.plugin_spec(%{
             connection_id: "conn-gh",
             enabled_actions: ["github_issue_fetch"]
           }).actions == [IssueFetch]
  end
end
