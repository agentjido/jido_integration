defmodule Jido.RuntimeControl.RuntimeFacadeTest do
  use ExUnit.Case, async: false

  alias Jido.RuntimeControl.RunRequest
  alias Jido.RuntimeControl.Test.{RuntimeBackedAdapterStub, RuntimeDriverStub}

  setup do
    old_providers = Application.get_env(:jido_runtime_control, :providers)
    old_default_provider = Application.get_env(:jido_runtime_control, :default_provider)
    old_runtime_drivers = Application.get_env(:jido_runtime_control, :runtime_drivers)
    old_default_runtime_driver = Application.get_env(:jido_runtime_control, :default_runtime_driver)

    on_exit(fn ->
      restore_env(:jido_runtime_control, :providers, old_providers)
      restore_env(:jido_runtime_control, :default_provider, old_default_provider)
      restore_env(:jido_runtime_control, :runtime_drivers, old_runtime_drivers)
      restore_env(:jido_runtime_control, :default_runtime_driver, old_default_runtime_driver)
    end)

    :ok
  end

  test "driver-first facade routes pure runtime drivers without adapter behaviour" do
    Application.put_env(:jido_runtime_control, :runtime_drivers, %{stub_runtime: RuntimeDriverStub})
    Application.put_env(:jido_runtime_control, :default_runtime_driver, :stub_runtime)

    request =
      RunRequest.new!(%{
        prompt: "hello through runtime",
        cwd: "/tmp/runtime-project",
        metadata: %{}
      })

    assert {:ok, session} =
             Jido.RuntimeControl.start_session(
               provider: :stub_runtime,
               session_id: "runtime-session-1",
               cwd: "/tmp/runtime-project"
             )

    refute Map.has_key?(Map.from_struct(session), :driver_ref)

    assert {:ok, run, stream} = Jido.RuntimeControl.stream_run(session, request, run_id: "runtime-run-1")
    assert {:ok, status} = Jido.RuntimeControl.session_status(session)
    assert {:ok, result} = Jido.RuntimeControl.run_result(session, request, run_id: "runtime-run-2")
    assert :ok = Jido.RuntimeControl.approve(session, "approval-1", :allow, source: "runtime-facade-test")
    assert {:ok, cost} = Jido.RuntimeControl.cost(session)
    assert :ok = Jido.RuntimeControl.cancel_run(session, run)
    assert :ok = Jido.RuntimeControl.stop_session(session)

    events = Enum.to_list(stream)

    assert_receive {:runtime_driver_stub_start_session, start_opts}
    assert start_opts[:cwd] == "/tmp/runtime-project"
    assert start_opts[:provider] == :stub_runtime

    assert_receive {:runtime_driver_stub_stream_run, "runtime-session-1", ^request, [run_id: "runtime-run-1"]}
    assert_receive {:runtime_driver_stub_run, "runtime-session-1", ^request, [run_id: "runtime-run-2"]}

    assert_receive {:runtime_driver_stub_approve, "runtime-session-1", "approval-1", :allow,
                    [source: "runtime-facade-test"]}

    assert_receive {:runtime_driver_stub_cost, "runtime-session-1"}
    assert_receive {:runtime_driver_stub_cancel_run, "runtime-session-1", "runtime-run-1"}
    assert_receive {:runtime_driver_stub_stop_session, "runtime-session-1"}

    assert status.state == :ready
    assert result.run_id == "runtime-run-2"
    assert cost["cost_usd"] == 0.01

    assert [
             %Jido.RuntimeControl.ExecutionEvent{type: :run_started},
             %Jido.RuntimeControl.ExecutionEvent{type: :result}
           ] = events
  end

  test "legacy run_request/3 keeps runtime-backed adapters working through provider config" do
    Application.put_env(:jido_runtime_control, :providers, %{runtime_adapter: RuntimeBackedAdapterStub})

    request =
      RunRequest.new!(%{
        prompt: "hello through runtime",
        cwd: "/tmp/runtime-project",
        metadata: %{}
      })

    assert {:ok, stream} = Jido.RuntimeControl.run_request(:runtime_adapter, request, transport: :exec)
    events = Enum.to_list(stream)

    assert_receive {:runtime_backed_adapter_start_session, start_opts}
    assert start_opts[:cwd] == "/tmp/runtime-project"
    assert start_opts[:transport] == :exec

    assert_receive {:runtime_backed_adapter_stream_run, "runtime-session-1", ^request, [transport: :exec]}
    refute_receive {:runtime_backed_adapter_legacy_run, _, _}
    assert_receive {:runtime_backed_adapter_stop_session, "runtime-session-1"}

    assert [%Jido.RuntimeControl.Event{type: :run_started}, %Jido.RuntimeControl.Event{type: :result}] = events
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
