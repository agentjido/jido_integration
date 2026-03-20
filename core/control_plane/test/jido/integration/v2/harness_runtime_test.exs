defmodule Jido.Integration.V2.HarnessRuntimeTest do
  use ExUnit.Case

  alias Jido.Harness.{ExecutionResult, SessionHandle}
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.HarnessRuntime
  alias Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver
  alias Jido.Integration.V2.TargetDescriptor

  defmodule AuthoredDriver do
    alias Jido.Harness.{ExecutionResult, RunRequest, SessionHandle}

    def start_session(opts) when is_list(opts) do
      send(self(), {:authored_driver_start_session, opts})

      {:ok,
       SessionHandle.new!(%{
         session_id: "authored-session",
         runtime_id: :authored_driver,
         provider: Keyword.get(opts, :provider),
         status: :ready,
         metadata: %{}
       })}
    end

    def run(%SessionHandle{} = session, %RunRequest{} = request, opts) when is_list(opts) do
      send(self(), {:authored_driver_run, session.session_id, request.prompt, opts})

      {:ok,
       ExecutionResult.new!(%{
         run_id: Keyword.get(opts, :run_id, "authored-run"),
         session_id: session.session_id,
         runtime_id: session.runtime_id,
         provider: session.provider,
         status: :completed,
         text: request.prompt,
         messages: [],
         cost: %{},
         stop_reason: "completed",
         metadata: %{}
       })}
    end

    def stop_session(%SessionHandle{}), do: :ok
  end

  defmodule OverrideDriver do
    alias Jido.Harness.{ExecutionResult, RunRequest, SessionHandle}

    def start_session(opts) when is_list(opts) do
      send(self(), {:override_driver_start_session, opts})

      {:ok,
       SessionHandle.new!(%{
         session_id: "override-session",
         runtime_id: :override_driver,
         provider: Keyword.get(opts, :provider),
         status: :ready,
         metadata: %{}
       })}
    end

    def run(%SessionHandle{} = session, %RunRequest{} = request, opts) when is_list(opts) do
      send(self(), {:override_driver_run, session.session_id, request.prompt, opts})

      {:ok,
       ExecutionResult.new!(%{
         run_id: Keyword.get(opts, :run_id, "override-run"),
         session_id: session.session_id,
         runtime_id: session.runtime_id,
         provider: session.provider,
         status: :completed,
         text: request.prompt,
         messages: [],
         cost: %{},
         stop_reason: "completed",
         metadata: %{}
       })}
    end

    def stop_session(%SessionHandle{}), do: :ok
  end

  setup do
    previous_runtime_drivers =
      Application.get_env(:jido_integration_v2_control_plane, :runtime_drivers)

    HarnessRuntime.reset!()

    on_exit(fn ->
      case previous_runtime_drivers do
        nil ->
          Application.delete_env(:jido_integration_v2_control_plane, :runtime_drivers)

        runtime_drivers ->
          Application.put_env(
            :jido_integration_v2_control_plane,
            :runtime_drivers,
            runtime_drivers
          )
      end

      HarnessRuntime.reset!()
    end)

    :ok
  end

  test "publishes asm and jido_session as the only target Harness driver ids" do
    assert HarnessRuntime.target_driver_ids() == ["asm", "jido_session"]
  end

  test "keeps integration-owned bridge drivers available only as compatibility shims" do
    assert HarnessRuntime.compatibility_driver_ids() == [
             "integration_session_bridge",
             "integration_stream_bridge"
           ]

    assert {:ok, Jido.Integration.V2.SessionKernel.HarnessDriver} =
             HarnessRuntime.driver_module("integration_session_bridge")

    assert {:ok, Jido.Integration.V2.StreamRuntime.HarnessDriver} =
             HarnessRuntime.driver_module("integration_stream_bridge")
  end

  test "resolves asm to the target Harness runtime driver" do
    assert {:ok, HarnessDriver} = HarnessRuntime.driver_module("asm")
    assert {:ok, Jido.Session.HarnessDriver} = HarnessRuntime.driver_module("jido_session")
  end

  test "passes authored runtime options through to the selected Harness driver" do
    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      %{authored_driver: AuthoredDriver}
    )

    assert {:ok, _result} =
             HarnessRuntime.execute(
               capability_fixture(%{
                 runtime: %{
                   driver: "authored_driver",
                   provider: :codex,
                   options: %{
                     "lane" => "sdk",
                     "approval_mode" => "manual"
                   }
                 }
               }),
               %{prompt: "hello"},
               runtime_context()
             )

    assert_receive {:authored_driver_start_session, start_opts}
    assert start_opts[:provider] == :codex
    assert start_opts[:lane] == "sdk"
    assert start_opts[:approval_mode] == "manual"

    assert_receive {:authored_driver_run, "authored-session", "hello", run_opts}
    assert run_opts[:provider] == :codex
    assert run_opts[:lane] == "sdk"
    assert run_opts[:approval_mode] == "manual"
  end

  test "does not let target descriptors override authored routing metadata" do
    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      %{
        authored_driver: AuthoredDriver,
        override_driver: OverrideDriver
      }
    )

    assert {:ok, _result} =
             HarnessRuntime.execute(
               capability_fixture(),
               %{prompt: "hello"},
               runtime_context(
                 target_descriptor_fixture(%{
                   "driver" => "override_driver",
                   "provider" => "claude",
                   "options" => %{"lane" => "target"}
                 })
               )
             )

    assert_receive {:authored_driver_start_session, start_opts}
    assert start_opts[:provider] == :codex
    refute_received {:override_driver_start_session, _opts}

    assert_receive {:authored_driver_run, "authored-session", "hello", run_opts}
    assert run_opts[:provider] == :codex
    refute_received {:override_driver_run, _session_id, _prompt, _opts}
  end

  defp capability_fixture(overrides \\ %{}) do
    runtime =
      Map.get(overrides, :runtime, %{
        driver: "authored_driver",
        provider: :codex,
        options: %{
          "lane" => "sdk"
        }
      })

    Capability.new!(%{
      id: "test.session.exec",
      connector: "test",
      runtime_class: :session,
      kind: :operation,
      transport_profile: :stdio,
      handler: __MODULE__,
      metadata: %{
        runtime: runtime
      }
    })
  end

  defp runtime_context(target_descriptor \\ nil) do
    %{
      run_id: "run-1",
      attempt_id: "run-1:1",
      credential_ref: %{id: "cred-1"},
      target_descriptor: target_descriptor,
      policy_inputs: %{
        execution: %{
          sandbox: %{
            allowed_tools: ["test.session.exec"],
            file_scope: "/tmp/runtime"
          }
        }
      }
    }
  end

  defp target_descriptor_fixture(runtime_extensions) do
    TargetDescriptor.new!(%{
      target_id: "target-1",
      capability_id: "test.session.exec",
      runtime_class: :session,
      version: "1.0.0",
      features: %{
        feature_ids: ["test.session.exec"],
        runspec_versions: ["1.0.0"],
        event_schema_versions: ["1.0.0"]
      },
      constraints: %{},
      health: :healthy,
      location: %{mode: :beam, region: "test", workspace_root: "/tmp/runtime"},
      extensions: %{"runtime" => runtime_extensions}
    })
  end
end
