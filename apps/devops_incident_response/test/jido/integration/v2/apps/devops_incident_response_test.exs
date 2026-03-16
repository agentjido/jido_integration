defmodule Jido.Integration.V2.Apps.DevopsIncidentResponseTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.TestTmpDir
  alias Jido.Integration.V2.Apps.DevopsIncidentResponse

  setup do
    runtime_root = TestTmpDir.create!("jido_devops_incident_response_test")

    on_exit(fn -> TestTmpDir.cleanup!(runtime_root) end)

    %{runtime_root: runtime_root}
  end

  test "proves install provisioning, hosted route wiring, async dead-letter replay, and restart recovery",
       %{runtime_root: runtime_root} do
    assert {:ok, runtime} =
             DevopsIncidentResponse.boot(%{
               runtime_root: runtime_root,
               max_attempts: 2,
               backoff_base_ms: 10,
               backoff_cap_ms: 10
             })

    assert {:ok, install} =
             DevopsIncidentResponse.provision_install(runtime, %{
               tenant_id: "tenant-devops",
               actor_id: "pager-operator",
               subject: "octocat",
               granted_scopes: ["repo"],
               webhook_secret: "incident-secret"
             })

    assert install.install.state == :completed
    assert install.connection.state == :connected
    assert install.route.install_id == install.install.install_id

    assert {:ok, route} =
             DevopsIncidentResponse.fetch_route(runtime, install.route.route_id)

    assert route.route_id == install.route.route_id
    assert route.callback_topology == :dynamic_per_install

    assert {:ok, accepted} =
             DevopsIncidentResponse.ingest_issue_webhook(
               runtime,
               install,
               %{
                 "action" => "opened",
                 "fail_attempts" => 2,
                 "issue" => %{"number" => 101, "title" => "Database latency spike"},
                 "repository" => %{"full_name" => "acme/api"}
               },
               delivery_id: "delivery-dead-letter"
             )

    assert accepted.dispatch_status == :accepted

    dead_lettered_dispatch =
      DevopsIncidentResponse.wait_for_dispatch(
        runtime,
        accepted.dispatch.dispatch_id,
        fn dispatch ->
          dispatch.status == :dead_lettered
        end
      )

    assert dead_lettered_dispatch.attempts == 2

    runtime = DevopsIncidentResponse.restart_dispatch_runtime(runtime)

    assert {:ok, replayed_dispatch} =
             DevopsIncidentResponse.replay_dispatch(runtime, dead_lettered_dispatch.dispatch_id)

    assert replayed_dispatch.status in [:queued, :retry_scheduled, :running]

    replayed_run =
      DevopsIncidentResponse.wait_for_run(runtime, accepted.run.run_id, fn run ->
        run.status == :completed
      end)

    assert replayed_run.result["incident_key"] == "acme/api#101"
    assert replayed_run.result["attempt"] == 3

    assert {:ok, completed_dispatch} =
             DevopsIncidentResponse.ingest_issue_webhook(
               runtime,
               install,
               %{
                 "action" => "opened",
                 "sleep_ms" => 500,
                 "issue" => %{"number" => 102, "title" => "Queue pressure"},
                 "repository" => %{"full_name" => "acme/api"}
               },
               delivery_id: "delivery-restart"
             )

    _running_dispatch =
      DevopsIncidentResponse.wait_for_dispatch(
        runtime,
        completed_dispatch.dispatch.dispatch_id,
        fn dispatch ->
          dispatch.status == :running
        end
      )

    runtime = DevopsIncidentResponse.restart_dispatch_runtime(runtime)

    recovered_dispatch =
      DevopsIncidentResponse.wait_for_dispatch(
        runtime,
        completed_dispatch.dispatch.dispatch_id,
        fn dispatch ->
          dispatch.status == :completed
        end
      )

    assert recovered_dispatch.attempts == 2

    restarted_run =
      DevopsIncidentResponse.wait_for_run(runtime, completed_dispatch.run.run_id, fn run ->
        run.status == :completed
      end)

    assert restarted_run.result["incident_key"] == "acme/api#102"
    assert restarted_run.result["attempt"] == 2
  end
end
