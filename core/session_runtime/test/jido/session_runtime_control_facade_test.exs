defmodule Jido.Session.RuntimeControlFacadeTest do
  use ExUnit.Case, async: false

  alias Jido.RuntimeControl.RunRequest

  setup do
    old_runtime_drivers = Application.get_env(:jido_runtime_control, :runtime_drivers)

    old_default_runtime_driver =
      Application.get_env(:jido_runtime_control, :default_runtime_driver)

    on_exit(fn ->
      restore_env(:jido_runtime_control, :runtime_drivers, old_runtime_drivers)
      restore_env(:jido_runtime_control, :default_runtime_driver, old_default_runtime_driver)
    end)

    :ok
  end

  test "routes runtime-backed sessions through the driver-first runtime-control facade" do
    Application.put_env(:jido_runtime_control, :runtime_drivers, %{
      jido_session: Jido.Session.RuntimeControlDriver
    })

    Application.put_env(:jido_runtime_control, :default_runtime_driver, :jido_session)

    request =
      RunRequest.new!(%{
        prompt: "through runtime_control",
        cwd: "/tmp/runtime-control-project",
        metadata: %{"suite" => "facade"}
      })

    assert {:ok, session} =
             Jido.RuntimeControl.start_session(
               session_id: "runtime-control-session-1",
               provider: :jido_session,
               cwd: "/tmp/runtime-control-project"
             )

    refute Map.has_key?(Map.from_struct(session), :driver_ref)

    assert {:ok, run, stream} =
             Jido.RuntimeControl.stream_run(session, request, run_id: "runtime-control-run-1")

    assert {:ok, result} =
             Jido.RuntimeControl.run_result(session, request, run_id: "runtime-control-run-2")

    assert {:ok, status} = Jido.RuntimeControl.session_status(session)
    assert :ok = Jido.RuntimeControl.stop_session(session)

    events = Enum.to_list(stream)

    assert run.run_id == "runtime-control-run-1"
    assert Enum.map(events, & &1.type) == [:run_started, :assistant_message, :result]
    assert Enum.all?(events, &match?(%Jido.RuntimeControl.ExecutionEvent{}, &1))

    assert Enum.at(events, 0).session_id == "runtime-control-session-1"
    assert Enum.at(events, 0).payload["prompt"] == "through runtime_control"
    assert Enum.at(events, 2).payload["text"] == "handled: through runtime_control"

    assert result.run_id == "runtime-control-run-2"
    assert result.text == "handled: through runtime_control"
    assert status.state == :ready
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
