defmodule Jido.RuntimeControlTest do
  use ExUnit.Case, async: false

  alias Jido.RuntimeControl.{Event, RunRequest}

  alias Jido.RuntimeControl.Test.{
    AdapterStub,
    ErrorRunnerStub,
    InvalidEventRunnerStub,
    NoCancelStub,
    NoRuntimeContractAdapterStub
  }

  setup do
    old_providers = Application.get_env(:jido_runtime_control, :providers)
    old_default = Application.get_env(:jido_runtime_control, :default_provider)
    old_runtime_drivers = Application.get_env(:jido_runtime_control, :runtime_drivers)
    old_default_runtime_driver = Application.get_env(:jido_runtime_control, :default_runtime_driver)

    on_exit(fn ->
      restore_env(:jido_runtime_control, :providers, old_providers)
      restore_env(:jido_runtime_control, :default_provider, old_default)
      restore_env(:jido_runtime_control, :runtime_drivers, old_runtime_drivers)
      restore_env(:jido_runtime_control, :default_runtime_driver, old_default_runtime_driver)
    end)

    :ok
  end

  test "run/3 returns error for unavailable provider" do
    Application.put_env(:jido_runtime_control, :providers, %{})

    assert {:error, %Jido.RuntimeControl.Error.ProviderNotFoundError{provider: :nonexistent}} =
             Jido.RuntimeControl.run(:nonexistent, "hello")
  end

  test "run/2 returns validation error when no default provider is configured" do
    Application.put_env(:jido_runtime_control, :providers, %{})
    Application.delete_env(:jido_runtime_control, :default_provider)

    assert {:error, %Jido.RuntimeControl.Error.InvalidInputError{field: :default_provider}} =
             Jido.RuntimeControl.run("hello", [])
  end

  test "run/3 delegates to configured adapter modules" do
    Application.put_env(:jido_runtime_control, :providers, %{stub: AdapterStub})
    request_opts = [cwd: "/tmp/project"]
    runtime_opts = [transport: :exec]

    assert {:ok, stream} = Jido.RuntimeControl.run(:stub, "hello", request_opts ++ runtime_opts)
    events = Enum.to_list(stream)

    assert_receive {:adapter_stub_run, request, [transport: :exec]}
    assert request.prompt == "hello"
    assert request.cwd == "/tmp/project"
    assert [%Event{type: :session_started}] = events
  end

  test "run/2 uses configured default provider" do
    Application.put_env(:jido_runtime_control, :providers, %{stub: AdapterStub})
    Application.put_env(:jido_runtime_control, :default_provider, :stub)

    assert {:ok, stream} = Jido.RuntimeControl.run("hello", [])
    assert [%Event{type: :session_started}] = Enum.to_list(stream)
  end

  test "run_request/3 delegates to adapter run/2 with RunRequest input" do
    Application.put_env(:jido_runtime_control, :providers, %{stub: AdapterStub})
    request = RunRequest.new!(%{prompt: "hello", metadata: %{}})

    assert {:ok, stream} = Jido.RuntimeControl.run_request(:stub, request, turn: 1)
    events = Enum.to_list(stream)

    assert_receive {:adapter_stub_run, ^request, [turn: 1]}
    assert [%Event{type: :session_started}] = events
  end

  test "run_request/3 returns provider-not-found for non-adapter modules" do
    Application.put_env(:jido_runtime_control, :providers, %{unsupported: NoRuntimeContractAdapterStub})
    request = RunRequest.new!(%{prompt: "hello", metadata: %{}})

    assert {:error, %Jido.RuntimeControl.Error.ProviderNotFoundError{provider: :unsupported}} =
             Jido.RuntimeControl.run_request(:unsupported, request, [])
  end

  test "run_request/2 returns validation error when no default provider is configured" do
    Application.put_env(:jido_runtime_control, :providers, %{})
    Application.delete_env(:jido_runtime_control, :default_provider)
    request = RunRequest.new!(%{prompt: "hello", metadata: %{}})

    assert {:error, %Jido.RuntimeControl.Error.InvalidInputError{field: :default_provider}} =
             Jido.RuntimeControl.run_request(request, [])
  end

  test "capabilities/1 delegates to adapter capabilities when present" do
    Application.put_env(:jido_runtime_control, :providers, %{stub: AdapterStub})

    assert {:ok, capabilities} = Jido.RuntimeControl.capabilities(:stub)
    assert capabilities.tool_calls? == true
    assert capabilities.cancellation? == true
  end

  test "capabilities/1 returns provider-not-found for non-adapter modules" do
    Application.put_env(:jido_runtime_control, :providers, %{unsupported: NoRuntimeContractAdapterStub})

    assert {:error, %Jido.RuntimeControl.Error.ProviderNotFoundError{provider: :unsupported}} =
             Jido.RuntimeControl.capabilities(:unsupported)
  end

  test "cancel/2 delegates to provider cancel when supported" do
    Application.put_env(:jido_runtime_control, :providers, %{stub: AdapterStub})

    assert :ok = Jido.RuntimeControl.cancel(:stub, "session-1")
    assert_receive {:adapter_stub_cancel, "session-1"}
  end

  test "cancel/2 returns structured error when unsupported" do
    Application.put_env(:jido_runtime_control, :providers, %{no_cancel: NoCancelStub})

    assert {:error, %Jido.RuntimeControl.Error.ExecutionFailureError{}} =
             Jido.RuntimeControl.cancel(:no_cancel, "session-1")
  end

  test "cancel/2 validates invalid session ids" do
    Application.put_env(:jido_runtime_control, :providers, %{stub: AdapterStub})
    assert {:error, %Jido.RuntimeControl.Error.InvalidInputError{}} = Jido.RuntimeControl.cancel(:stub, "")
  end

  test "capabilities/1 returns provider-not-found for missing providers" do
    Application.put_env(:jido_runtime_control, :providers, %{})

    assert {:error, %Jido.RuntimeControl.Error.ProviderNotFoundError{provider: :missing}} =
             Jido.RuntimeControl.capabilities(:missing)
  end

  test "providers/0 returns provider metadata list" do
    Application.put_env(:jido_runtime_control, :providers, %{
      stub: AdapterStub
    })

    providers = Jido.RuntimeControl.providers()
    assert Enum.any?(providers, &(&1.id == :stub))
  end

  test "default_provider/0 delegates to registry default provider" do
    Application.put_env(:jido_runtime_control, :providers, %{stub: AdapterStub})
    Application.put_env(:jido_runtime_control, :default_provider, :stub)
    assert Jido.RuntimeControl.default_provider() == :stub
  end

  test "run/3 passes through provider error tuples" do
    Application.put_env(:jido_runtime_control, :providers, %{error_runner: ErrorRunnerStub})
    assert {:error, :boom} = Jido.RuntimeControl.run(:error_runner, "hello")
  end

  test "run/3 enforces stream entries are normalized events" do
    Application.put_env(:jido_runtime_control, :providers, %{invalid_events: InvalidEventRunnerStub})

    assert {:ok, stream} = Jido.RuntimeControl.run(:invalid_events, "hello")
    assert_receive {:invalid_event_runner_run, "hello", _opts}

    assert_raise ArgumentError, fn ->
      Enum.to_list(stream)
    end
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
