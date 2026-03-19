defmodule Jido.Integration.V2.Connectors.GitHub.GeneratedConsumerSurfaceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.GitHub.Generated.Actions.IssueFetch
  alias Jido.Integration.V2.Connectors.GitHub.Generated.Actions.IssueList
  alias Jido.Integration.V2.Connectors.GitHub.Generated.Plugin, as: GeneratedPlugin
  alias Jido.Integration.V2.Connectors.GitHub.Fixtures
  alias Jido.Integration.V2.ConsumerProjection
  alias Jido.Integration.V2.Contracts
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

  setup do
    ensure_started(
      [Jido.Integration.V2.ControlPlane.Registry, Jido.Integration.V2.ControlPlane.RunLedger],
      Jido.Integration.V2.ControlPlane.Supervisor,
      Jido.Integration.V2.ControlPlane.Application
    )

    ensure_started(
      [Jido.Integration.V2.Auth.Store],
      Jido.Integration.V2.Auth.Supervisor,
      Jido.Integration.V2.Auth.Application
    )

    ensure_started(
      [Jido.Integration.V2.SessionKernel.SessionStore],
      Jido.Integration.V2.SessionKernel.Supervisor,
      Jido.Integration.V2.SessionKernel.Application
    )

    ensure_started(
      [Jido.Integration.V2.StreamRuntime.Store],
      Jido.Integration.V2.StreamRuntime.Supervisor,
      Jido.Integration.V2.StreamRuntime.Application
    )

    V2.reset!()
    :ok
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

  test "generated actions invoke the public facade with typed request bindings from params or plugin config" do
    projection = IssueFetch.generated_action_projection()

    assert {:ok, _parsed_input} =
             Zoi.parse(IssueFetch.schema(), %{repo: "acme/widgets", issue_number: 7})

    assert {:error, _reason} =
             Zoi.parse(IssueFetch.schema(), %{repo: "widgets"})

    assert {:error, _reason} =
             Zoi.parse(IssueFetch.schema(), %{repo: "acme/widgets/extra", issue_number: 7})

    assert {:error, _reason} =
             Zoi.parse(IssueFetch.schema(), %{repo: "acme/widgets", issue_number: 0})

    assert {:error, _reason} =
             Zoi.parse(IssueList.schema(), %{repo: "acme/widgets", page: 0, per_page: 2})

    assert {:error, _reason} =
             Zoi.parse(IssueList.schema(), %{repo: "acme/widgets", page: 1, per_page: -1})

    assert %InvocationRequest{
             capability_id: "github.issue.fetch",
             connection_id: "conn-param",
             input: %{repo: "acme/widgets", issue_number: 7},
             trace_id: "trace-generated-1"
           } =
             ConsumerProjection.invocation_request!(
               projection,
               %{repo: "acme/widgets", issue_number: 7, connection_id: "conn-param"},
               %{trace_id: "trace-generated-1"}
             )

    assert %InvocationRequest{
             capability_id: "github.issue.fetch",
             connection_id: "conn-plugin",
             input: %{repo: "acme/widgets", issue_number: 8}
           } =
             ConsumerProjection.invocation_request!(
               projection,
               %{repo: "acme/widgets", issue_number: 8},
               %{plugin_config: %{connection_id: "conn-plugin"}}
             )

    assert {:error, _reason} =
             IssueFetch.run(
               %{repo: "acme/widgets", issue_number: 7, connection_id: "conn-param"},
               %{invoker: FakeInvoker, trace_id: "trace-generated-1"}
             )

    refute_receive {:generated_invoke, _request}
  end

  test "generated actions execute the full GitHub A0 slice through the real facade" do
    register_connector!()
    connection_id = install_connection!()

    Enum.each(Fixtures.specs(), fn spec ->
      capability = fetch_capability!(spec.capability_id)
      action_module = ConsumerProjection.action_module(GitHub, spec.capability_id)

      assert {:ok, output} =
               action_module.run(
                 Map.put(spec.input, :connection_id, connection_id),
                 %{
                   invoke: %{
                     actor_id: "generated-consumer",
                     tenant_id: "tenant-generated-github",
                     environment: :prod,
                     trace_id: "trace-#{String.replace(spec.capability_id, ".", "-")}",
                     allowed_operations: [spec.capability_id],
                     sandbox: capability.metadata.policy.sandbox,
                     extensions: [github_client: Fixtures.client_opts(self())]
                   }
                 }
               )

      assert output == spec.output

      assert_receive {:transport_request, request, _context}
      Fixtures.assert_request(spec.capability_id, request)
    end)
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

  defp register_connector! do
    assert :ok = V2.register_connector(GitHub)
  end

  defp install_connection! do
    now = Contracts.now()

    assert {:ok, %{install: install, connection: connection}} =
             V2.start_install("github", "tenant-generated-github", %{
               actor_id: "generated-consumer",
               auth_type: :oauth2,
               subject: "octocat",
               requested_scopes: ["repo"],
               now: now
             })

    assert {:ok,
            %{install: %{install_id: install_id}, connection: %{connection_id: connection_id}}} =
             V2.complete_install(install.install_id, %{
               subject: "octocat",
               granted_scopes: ["repo"],
               secret: %{access_token: Fixtures.access_token()},
               expires_at: DateTime.add(now, 7 * 24 * 3_600, :second),
               now: now
             })

    assert install_id == install.install_id
    assert connection_id == connection.connection_id
    connection_id
  end

  defp fetch_capability!(capability_id) do
    Enum.find(GitHub.manifest().capabilities, &(&1.id == capability_id)) ||
      raise "missing capability #{capability_id}"
  end

  defp ensure_started(required_processes, supervisor_name, application_module) do
    if Enum.all?(required_processes, &Process.whereis/1) do
      :ok
    else
      if pid = Process.whereis(supervisor_name) do
        try do
          GenServer.stop(pid, :normal)
        catch
          :exit, _reason -> :ok
        end
      end

      case application_module.start(:normal, []) do
        {:ok, _pid} ->
          :ok

        {:error, {:already_started, _pid}} ->
          :ok

        {:error, reason} ->
          raise "failed to start #{inspect(supervisor_name)}: #{inspect(reason)}"
      end
    end
  end
end
