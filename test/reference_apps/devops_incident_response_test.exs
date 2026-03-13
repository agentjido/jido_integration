defmodule DevopsIncidentResponseTest do
  use ExUnit.Case, async: false

  alias DevopsIncidentResponse.Runtime

  @moduletag :tmp_dir

  test "proves auth, trigger, durable dispatch, replay, and recovery across consumer restart", %{
    tmp_dir: tmp_dir
  } do
    {:ok, runtime} = Runtime.boot(dir: tmp_dir, max_attempts: 1)
    {:ok, install} = Runtime.provision_install(runtime)

    {:ok, accepted} =
      Runtime.ingest_issue_webhook(
        runtime,
        install,
        %{
          "action" => "opened",
          "simulate" => "slow",
          "issue" => %{"number" => 101, "title" => "Database latency spike"},
          "repository" => %{"full_name" => "acme/api"}
        },
        delivery_id: "recovery_delivery_001"
      )

    runtime = Runtime.restart_consumer(runtime)
    recovered = Runtime.wait_for_run(runtime, accepted["run_id"], &(&1.status == :succeeded))

    assert recovered.result["incident_key"] == "acme/api#101"
    assert recovered.attempt == 1

    {:ok, replay_accepted} =
      Runtime.ingest_issue_webhook(
        runtime,
        install,
        %{
          "action" => "opened",
          "simulate" => "fail_once",
          "issue" => %{"number" => 102, "title" => "Worker saturation"},
          "repository" => %{"full_name" => "acme/api"}
        },
        delivery_id: "replay_delivery_001"
      )

    dead_lettered =
      Runtime.wait_for_run(runtime, replay_accepted["run_id"], &(&1.status == :dead_lettered))

    assert dead_lettered.attempt == 1
    runtime = Runtime.restart_consumer(runtime)
    assert {:ok, replayed_run_id} = Runtime.replay(runtime, dead_lettered.run_id)
    assert replayed_run_id == dead_lettered.run_id

    replayed = Runtime.wait_for_run(runtime, dead_lettered.run_id, &(&1.status == :succeeded))

    assert replayed.attempt == 2
    assert replayed.result["summary"] == "Worker saturation"
  end
end
