defmodule Jido.Session.HarnessFacadeTest do
  use ExUnit.Case, async: false

  alias Jido.Harness.RunRequest

  setup do
    old_runtime_drivers = Application.get_env(:jido_harness, :runtime_drivers)
    old_default_runtime_driver = Application.get_env(:jido_harness, :default_runtime_driver)

    on_exit(fn ->
      restore_env(:jido_harness, :runtime_drivers, old_runtime_drivers)
      restore_env(:jido_harness, :default_runtime_driver, old_default_runtime_driver)
    end)

    :ok
  end

  test "routes runtime-backed sessions through the driver-first harness facade" do
    Application.put_env(:jido_harness, :runtime_drivers, %{
      jido_session: Jido.Session.HarnessDriver
    })

    Application.put_env(:jido_harness, :default_runtime_driver, :jido_session)

    request =
      RunRequest.new!(%{
        prompt: "through harness",
        cwd: "/tmp/harness-project",
        metadata: %{"suite" => "facade"}
      })

    assert {:ok, session} =
             Jido.Harness.start_session(
               session_id: "harness-session-1",
               provider: :jido_session,
               cwd: "/tmp/harness-project"
             )

    refute Map.has_key?(Map.from_struct(session), :driver_ref)

    assert {:ok, run, stream} = Jido.Harness.stream_run(session, request, run_id: "harness-run-1")

    assert {:ok, result} = Jido.Harness.run_result(session, request, run_id: "harness-run-2")

    assert {:ok, status} = Jido.Harness.session_status(session)
    assert :ok = Jido.Harness.stop_session(session)

    events = Enum.to_list(stream)

    assert run.run_id == "harness-run-1"
    assert Enum.map(events, & &1.type) == [:run_started, :assistant_message, :result]
    assert Enum.all?(events, &match?(%Jido.Harness.ExecutionEvent{}, &1))

    assert Enum.at(events, 0).session_id == "harness-session-1"
    assert Enum.at(events, 0).payload["prompt"] == "through harness"
    assert Enum.at(events, 2).payload["text"] == "handled: through harness"

    assert result.run_id == "harness-run-2"
    assert result.text == "handled: through harness"
    assert status.state == :ready
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
