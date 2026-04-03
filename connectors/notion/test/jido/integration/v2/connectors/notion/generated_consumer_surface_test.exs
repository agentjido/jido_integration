defmodule Jido.Integration.V2.Connectors.Notion.GeneratedConsumerSurfaceTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2, as: V2
  alias Jido.Integration.V2.Connectors.Notion
  alias Jido.Integration.V2.Connectors.Notion.Fixtures
  alias Jido.Integration.V2.Connectors.Notion.FixtureTransport
  alias Jido.Integration.V2.ConsumerProjection
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.DirectRuntime
  alias Jido.Integration.V2.TriggerSpec
  alias Pristine.Core.Response

  @published_capability_ids Fixtures.published_capability_ids()

  setup do
    ensure_started(
      [
        Jido.Integration.V2.ControlPlane.Registry,
        Jido.Integration.V2.ControlPlane.RunLedger
      ],
      Jido.Integration.V2.ControlPlane.Supervisor,
      Jido.Integration.V2.ControlPlane.Application
    )

    ensure_started(
      [Jido.Integration.V2.Auth.Store],
      Jido.Integration.V2.Auth.Supervisor,
      Jido.Integration.V2.Auth.Application
    )

    V2.reset!()
    :ok
  end

  test "publishes the curated notion slice as generated common actions and a generated plugin bundle" do
    projected_operations = ConsumerProjection.projected_operations(Notion.manifest())

    assert Enum.map(projected_operations, & &1.operation_id) ==
             Enum.sort(@published_capability_ids)

    Enum.each(projected_operations, fn operation ->
      action_module = ConsumerProjection.action_module(Notion, operation.operation_id)

      assert Code.ensure_loaded?(action_module)
      assert function_exported?(action_module, :run, 2)
      assert function_exported?(action_module, :schema, 0)
      assert function_exported?(action_module, :output_schema, 0)
      assert action_module.operation_id() == operation.operation_id
      assert action_module.name() == operation.jido.action.name
      assert action_module.schema() == operation.input_schema
      assert action_module.output_schema() == operation.output_schema
    end)

    plugin_module = ConsumerProjection.plugin_module(Notion)

    assert Code.ensure_loaded?(plugin_module)
    assert function_exported?(plugin_module, :actions, 0)

    assert Enum.map(plugin_module.actions(), & &1.operation_id()) ==
             Enum.sort(@published_capability_ids)
  end

  test "generated notion actions execute through the public facade using the existing invoke path" do
    assert :ok = V2.register_connector(Notion)
    connection_id = install_connection!()

    Enum.each(@published_capability_ids, fn capability_id ->
      capability = fetch_capability!(capability_id)
      action_module = ConsumerProjection.action_module(Notion, capability_id)

      assert {:ok, output} =
               action_module.run(
                 Map.put(Fixtures.input_for(capability_id), :connection_id, connection_id),
                 %{
                   invoke: %{
                     actor_id: "generated-consumer",
                     tenant_id: "tenant-generated-notion",
                     environment: :prod,
                     trace_id: "trace-#{String.replace(capability_id, ".", "-")}",
                     allowed_operations: [capability_id],
                     sandbox: capability.metadata.policy.sandbox,
                     extensions: [
                       notion_client: [
                         transport: FixtureTransport,
                         transport_opts: [test_pid: self()]
                       ]
                     ]
                   }
                 }
               )

      assert output == %{
               capability_id: capability_id,
               auth_binding: Fixtures.auth_binding(),
               data: Fixtures.output_data(capability_id)
             }
    end)
  end

  test "publishes a generated common sensor and plugin subscription for recently edited pages" do
    manifest = Notion.manifest()
    [trigger] = manifest.triggers
    plugin_module = ConsumerProjection.plugin_module(Notion)
    sensor_module = ConsumerProjection.sensor_module(Notion, trigger.trigger_id)

    assert trigger.trigger_id == "notion.pages.recently_edited"
    assert TriggerSpec.common_consumer_surface?(trigger)

    assert trigger.checkpoint == %{
             strategy: :timestamp_cursor,
             field: "last_edited_time",
             partition_key: "workspace"
           }

    assert trigger.dedupe == %{
             strategy: :page_id_last_edited_time,
             fields: ["page_id", "last_edited_time"]
           }

    assert Code.ensure_loaded?(sensor_module)
    assert function_exported?(sensor_module, :init, 2)
    assert function_exported?(sensor_module, :handle_event, 2)

    assert plugin_module.subscriptions() == [{sensor_module, %{}}]
  end

  test "generated plugins materialize Notion poll subscriptions with invoke defaults and trigger config" do
    plugin_module = ConsumerProjection.plugin_module(Notion)
    sensor_module = ConsumerProjection.sensor_module(Notion, "notion.pages.recently_edited")

    assert [{^sensor_module, sensor_config}] =
             plugin_module.subscriptions(
               %{
                 connection_id: "conn-notion-1",
                 invoke_defaults: %{
                   tenant_id: "tenant-generated-notion",
                   actor_id: "generated-consumer",
                   environment: :staging,
                   extensions: %{
                     notion_client: [
                       transport: FixtureTransport,
                       transport_opts: [test_pid: self(), response: &recent_page_edits_response/2]
                     ]
                   }
                 },
                 trigger_subscriptions: %{
                   page_recently_edited: %{
                     enabled: true,
                     interval_ms: 45_000,
                     partition_key: "workspace",
                     config: %{page_size: 3}
                   }
                 }
               },
               %{agent_id: "agent-notion-1"}
             )

    assert sensor_config == %{
             actor_id: "generated-consumer",
             config: %{page_size: 3},
             connection_id: "conn-notion-1",
             environment: :staging,
             extensions: %{
               notion_client: [
                 transport: FixtureTransport,
                 transport_opts: [test_pid: self(), response: &recent_page_edits_response/2]
               ]
             },
             interval_ms: 45_000,
             partition_key: "workspace",
             tenant_id: "tenant-generated-notion"
           }
  end

  test "generated notion poll sensors execute the shared durable sensor tick path" do
    assert :ok = V2.register_connector(Notion)
    connection_id = install_connection!()
    sensor_module = ConsumerProjection.sensor_module(Notion, "notion.pages.recently_edited")

    assert {:ok, config} =
             Zoi.parse(sensor_module.schema(), %{
               connection_id: connection_id,
               tenant_id: "tenant-generated-notion",
               actor_id: "generated-consumer",
               partition_key: "workspace",
               interval_ms: 45_000,
               config: %{page_size: 3},
               extensions: %{
                 notion_client: [
                   transport: FixtureTransport,
                   transport_opts: [test_pid: self(), response: &recent_page_edits_response/2]
                 ]
               }
             })

    assert {:ok, state, [{:schedule, 45_000}]} = sensor_module.init(config, %{})

    assert {:ok, next_state,
            [
              {:emit, signal},
              {:emit, _second_signal},
              {:emit, _third_signal},
              {:schedule, 45_000}
            ]} =
             sensor_module.handle_event(:tick, state)

    assert signal.type == "notion.page.recently_edited"
    assert signal.source == "/ingress/poll/notion/pages.recently_edited"

    assert {:ok, checkpoint} =
             ControlPlane.fetch_trigger_checkpoint(
               "tenant-generated-notion",
               "notion",
               "notion.pages.recently_edited",
               "workspace"
             )

    assert checkpoint.cursor == "2026-03-12T10:00:00Z"

    assert checkpoint.last_event_id ==
             "00000000-0000-0000-0000-000000000010:2026-03-12T10:00:00Z"

    assert %DateTime{} = checkpoint.last_event_time

    assert {:ok, ^next_state, [{:schedule, 45_000}]} =
             sensor_module.handle_event(:tick, next_state)
  end

  test "recent page edits polling uses Notion Search and emits stable checkpoint and dedupe posture" do
    capability = fetch_capability!("notion.pages.recently_edited")

    assert {:ok, result} =
             DirectRuntime.execute(
               capability,
               %{
                 page_size: 3,
                 checkpoint_cursor: "2026-03-12T09:15:00Z"
               },
               Fixtures.execution_context("notion.pages.recently_edited",
                 notion_client: [
                   transport: FixtureTransport,
                   transport_opts: [
                     test_pid: self(),
                     response: &recent_page_edits_response/2
                   ]
                 ]
               )
             )

    assert_receive {:transport_request, request, _context}
    assert request.method == :post
    assert request.url == Fixtures.request_url("notion.search.search")
    assert request_body(request, "page_size") == 3
    assert request_body(request, "filter", "property") == "object"
    assert request_body(request, "filter", "value") == "page"
    assert request_body(request, "sort", "timestamp") == "last_edited_time"
    assert request_body(request, "sort", "direction") == "descending"

    assert result.output == %{
             capability_id: "notion.pages.recently_edited",
             auth_binding: Fixtures.auth_binding(),
             signals: [
               %{
                 page_id: "00000000-0000-0000-0000-000000000010",
                 last_edited_time: "2026-03-12T10:00:00Z",
                 title: "Deterministic publish page",
                 url: "https://www.notion.so/00000000-0000-0000-0000-000000000010"
               },
               %{
                 page_id: "00000000-0000-0000-0000-000000000011",
                 last_edited_time: "2026-03-12T09:30:00Z",
                 title: "Deterministic publish page v2",
                 url: "https://www.notion.so/00000000-0000-0000-0000-000000000011"
               }
             ],
             checkpoint: %{
               strategy: :timestamp_cursor,
               cursor: "2026-03-12T10:00:00Z"
             },
             dedupe_keys: [
               "00000000-0000-0000-0000-000000000010:2026-03-12T10:00:00Z",
               "00000000-0000-0000-0000-000000000011:2026-03-12T09:30:00Z"
             ]
           }

    assert Enum.map(result.events, & &1.type) == [
             "attempt.started",
             "connector.notion.pages.recently_edited.completed",
             "attempt.completed"
           ]

    assert [artifact] = result.artifacts

    assert artifact.payload_ref.key ==
             "notion/run-notion-test/run-notion-test:1/pages_recently_edited.term"
  end

  defp install_connection! do
    now = Contracts.now()
    auth = Notion.manifest().auth
    requested_scopes = auth.requested_scopes
    payload = Fixtures.credential_lease_attrs().payload

    assert {:ok, %{install: install}} =
             V2.start_install("notion", "tenant-generated-notion", %{
               actor_id: "generated-consumer",
               auth_type: auth.auth_type,
               profile_id: auth.default_profile,
               subject: "workspace:acme",
               requested_scopes: requested_scopes,
               now: now
             })

    assert {:ok, %{connection: %{connection_id: connection_id}}} =
             V2.complete_install(install.install_id, %{
               subject: "workspace:acme",
               granted_scopes: requested_scopes,
               secret: payload,
               expires_at: DateTime.add(now, 7 * 24 * 3_600, :second),
               now: now
             })

    connection_id
  end

  defp fetch_capability!(capability_id) do
    Enum.find(Notion.manifest().capabilities, &(&1.id == capability_id)) ||
      raise "missing capability #{capability_id}"
  end

  defp recent_page_edits_response(_request, _context) do
    {:ok,
     %Response{
       status: 200,
       headers: %{"content-type" => "application/json"},
       body:
         Jason.encode!(%{
           "object" => "list",
           "results" => [
             %{
               "object" => "page",
               "id" => "00000000-0000-0000-0000-000000000010",
               "url" => "https://www.notion.so/00000000-0000-0000-0000-000000000010",
               "last_edited_time" => "2026-03-12T10:00:00Z",
               "properties" => %{
                 "Title" => %{
                   "title" => [
                     %{"plain_text" => "Deterministic publish page"}
                   ]
                 }
               }
             },
             %{
               "object" => "page",
               "id" => "00000000-0000-0000-0000-000000000011",
               "url" => "https://www.notion.so/00000000-0000-0000-0000-000000000011",
               "last_edited_time" => "2026-03-12T09:30:00Z",
               "properties" => %{
                 "Title" => %{
                   "title" => [
                     %{"plain_text" => "Deterministic publish page v2"}
                   ]
                 }
               }
             },
             %{
               "object" => "page",
               "id" => "00000000-0000-0000-0000-000000000012",
               "url" => "https://www.notion.so/00000000-0000-0000-0000-000000000012",
               "last_edited_time" => "2026-03-12T09:00:00Z",
               "properties" => %{
                 "Title" => %{
                   "title" => [
                     %{"plain_text" => "Older page outside the checkpoint"}
                   ]
                 }
               }
             }
           ],
           "next_cursor" => nil,
           "has_more" => false
         })
     }}
  end

  defp request_body(request, key) do
    request
    |> request_body_map()
    |> then(fn body -> body[key] || body[String.to_atom(key)] || body[to_string(key)] end)
  end

  defp request_body(request, key, nested_key) do
    nested = request_body(request, key)
    nested[nested_key] || nested[String.to_atom(nested_key)] || nested[to_string(nested_key)]
  end

  defp request_body_map(%{body: body}) when is_binary(body), do: Jason.decode!(body)
  defp request_body_map(%{body: body}) when is_map(body), do: body

  defp ensure_started(required_processes, supervisor_name, application_module) do
    if Enum.all?(required_processes, &Process.whereis/1) do
      :ok
    else
      ensure_stopped(supervisor_name)

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

  defp ensure_stopped(supervisor_name) do
    if pid = Process.whereis(supervisor_name) do
      try do
        GenServer.stop(pid, :normal)
      catch
        :exit, _reason -> :ok
      end
    end
  end
end
