defmodule Jido.RuntimeControl.RuntimeFacadeTest do
  use ExUnit.Case, async: false

  alias Jido.RuntimeControl.RunRequest
  alias Jido.RuntimeControl.Test.RuntimeDriverStub

  setup do
    old_runtime_drivers = Application.get_env(:jido_runtime_control, :runtime_drivers)
    old_default_runtime_driver = Application.get_env(:jido_runtime_control, :default_runtime_driver)

    on_exit(fn ->
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

  test "runtime_drivers/0 returns normalized runtime descriptors" do
    Application.put_env(:jido_runtime_control, :runtime_drivers, %{stub_runtime: RuntimeDriverStub})

    assert [%Jido.RuntimeControl.RuntimeDescriptor{} = descriptor] = Jido.RuntimeControl.runtime_drivers()
    assert descriptor.runtime_id == :stub_runtime
    assert descriptor.provider == :stub_runtime
    assert descriptor.label == "Stub Runtime"
  end

  test "runtime_descriptor/2 delegates to the registered runtime driver" do
    Application.put_env(:jido_runtime_control, :runtime_drivers, %{stub_runtime: RuntimeDriverStub})

    assert {:ok, descriptor} = Jido.RuntimeControl.runtime_descriptor(:stub_runtime, provider: :alt_provider)
    assert descriptor.runtime_id == :stub_runtime
    assert descriptor.provider == :alt_provider
  end

  test "start_session/1 uses the configured default runtime driver" do
    Application.put_env(:jido_runtime_control, :runtime_drivers, %{stub_runtime: RuntimeDriverStub})
    Application.put_env(:jido_runtime_control, :default_runtime_driver, :stub_runtime)

    assert {:ok, session} =
             Jido.RuntimeControl.start_session(
               provider: :stub_runtime,
               session_id: "runtime-session-default"
             )

    assert session.runtime_id == :stub_runtime
    assert session.session_id == "runtime-session-default"

    assert_receive {:runtime_driver_stub_start_session, start_opts}
    assert start_opts[:provider] == :stub_runtime
    assert start_opts[:session_id] == "runtime-session-default"
  end

  test "start_session/1 returns validation error when no default runtime driver is configured" do
    Application.put_env(:jido_runtime_control, :runtime_drivers, %{})
    Application.delete_env(:jido_runtime_control, :default_runtime_driver)

    assert {:error, %Jido.RuntimeControl.Error.InvalidInputError{field: :default_runtime_driver}} =
             Jido.RuntimeControl.start_session([])
  end

  test "legacy provider facade functions are removed from Jido.RuntimeControl" do
    refute function_exported?(Jido.RuntimeControl, :providers, 0)
    refute function_exported?(Jido.RuntimeControl, :default_provider, 0)
    refute function_exported?(Jido.RuntimeControl, :run, 2)
    refute function_exported?(Jido.RuntimeControl, :run, 3)
    refute function_exported?(Jido.RuntimeControl, :run_request, 2)
    refute function_exported?(Jido.RuntimeControl, :run_request, 3)
    refute function_exported?(Jido.RuntimeControl, :capabilities, 1)
    refute function_exported?(Jido.RuntimeControl, :cancel, 2)
  end

  test "legacy provider modules are removed from runtime_control" do
    refute Code.ensure_loaded?(Jido.RuntimeControl.Registry)
    refute Code.ensure_loaded?(Jido.RuntimeControl.Adapter)
    refute Code.ensure_loaded?(Jido.RuntimeControl.AdapterContract)
    refute Code.ensure_loaded?(Jido.RuntimeControl.Provider)
    refute Code.ensure_loaded?(Jido.RuntimeControl.Capabilities)
    refute Code.ensure_loaded?(Jido.RuntimeControl.Event)
    refute Code.ensure_loaded?(Jido.RuntimeControl.RuntimeContract)
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
