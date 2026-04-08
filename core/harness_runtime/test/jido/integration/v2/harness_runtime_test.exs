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
    HarnessRuntime.start!()

    previous_runtime_drivers =
      Application.get_env(:jido_integration_v2_control_plane, :runtime_drivers)

    Application.delete_env(:jido_integration_v2_control_plane, :runtime_drivers)
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

  test "start!/0 boots the harness runtime and its declared runtime dependencies" do
    stop_harness_runtime!()

    assert :ok = HarnessRuntime.start!()
    assert :ok = HarnessRuntime.start!()

    assert Process.whereis(Jido.Integration.V2.HarnessRuntime.Supervisor)
    assert Process.whereis(Jido.Integration.V2.HarnessRuntime.SessionStore)
    assert Process.whereis(Jido.Integration.V2.RuntimeAsmBridge.SessionStore)
    assert Process.whereis(Jido.Session.Store)
  end

  test "publishes asm and jido_session as the only built-in Harness driver ids" do
    assert HarnessRuntime.target_driver_ids() == ["asm", "jido_session"]
    assert HarnessRuntime.driver_modules() |> Map.keys() |> Enum.sort() == ["asm", "jido_session"]
  end

  test "does not resolve removed bridge runtime drivers" do
    refute function_exported?(HarnessRuntime, :compatibility_driver_ids, 0)
    assert :error = HarnessRuntime.driver_module(removed_session_bridge_id())
    assert :error = HarnessRuntime.driver_module(removed_stream_bridge_id())
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

  test "requires an authored runtime driver for non-direct capabilities" do
    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      %{asm: AuthoredDriver}
    )

    assert {:error, {:missing_runtime_driver, :session}, runtime_result} =
             HarnessRuntime.execute(
               capability_fixture(%{
                 runtime: %{
                   provider: :codex,
                   options: %{
                     "lane" => "sdk"
                   }
                 }
               }),
               %{prompt: "hello"},
               runtime_context()
             )

    assert Enum.map(runtime_result.events, & &1.type) == ["attempt.started", "attempt.failed"]
    refute_received {:authored_driver_start_session, _opts}
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

  test "fails loudly when the harness runtime application is not started" do
    stop_harness_runtime!()

    Application.put_env(
      :jido_integration_v2_control_plane,
      :runtime_drivers,
      %{authored_driver: AuthoredDriver}
    )

    assert_raise ArgumentError, ~r/call Jido\.Integration\.V2\.HarnessRuntime\.start!\/0/, fn ->
      HarnessRuntime.execute(
        capability_fixture(),
        %{prompt: "hello"},
        runtime_context()
      )
    end
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

  defp removed_session_bridge_id, do: removed_bridge_id("session")
  defp removed_stream_bridge_id, do: removed_bridge_id("stream")

  defp removed_bridge_id(kind) do
    ["integration", kind, "bridge"]
    |> Enum.join("_")
  end

  defp stop_harness_runtime! do
    HarnessRuntime.stop!()
  end
end
