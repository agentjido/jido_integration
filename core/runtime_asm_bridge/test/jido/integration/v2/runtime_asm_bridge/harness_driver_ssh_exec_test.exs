defmodule Jido.Integration.V2.RuntimeAsmBridge.HarnessDriverSSHExecTest do
  use ExUnit.Case, async: false

  alias Jido.Harness.{ExecutionEvent, ExecutionResult, RunHandle, RunRequest}
  alias Jido.Integration.V2.RuntimeAsmBridge.{HarnessDriver, SessionStore}

  setup do
    SessionStore.reset!()
    :ok
  end

  test "stream_run/3 proves leased SSHExec through the unchanged harness driver seam" do
    manifest_path = temp_path!("stream_manifest.txt")
    ssh_path = create_fake_ssh!(manifest_path)
    cli_path = write_script!(codex_success_script("HARNESS_SSH_OK"))

    assert {:ok, session} =
             HarnessDriver.start_session(
               provider: :codex,
               surface_kind: :leased_ssh,
               lease_ref: "lease-1",
               surface_ref: "surface-1",
               target_id: "target-1",
               transport_options: [
                 ssh_path: ssh_path,
                 destination: "bridge.ssh.example",
                 port: 2222
               ]
             )

    on_exit(fn ->
      _ = HarnessDriver.stop_session(session)
    end)

    request = RunRequest.new!(%{prompt: "hello", metadata: %{}})

    assert {:ok, %RunHandle{} = run, stream} =
             HarnessDriver.stream_run(session, request, cli_path: cli_path)

    events = Enum.to_list(stream)

    assert [%ExecutionEvent{type: :run_started} | _] = events
    assert Enum.any?(events, &(&1.type == :assistant_message))
    assert List.last(events).type == :result
    assert run.runtime_id == :asm

    assert_eventually(fn -> File.exists?(manifest_path) end)
    manifest = File.read!(manifest_path)
    assert manifest =~ "destination=bridge.ssh.example"
    assert manifest =~ "port=2222"
    assert :ok = HarnessDriver.stop_session(session)
    assert :error = SessionStore.fetch(session.session_id)
  end

  test "cancel_run/2 interrupts the active leased SSHExec run end to end" do
    manifest_path = temp_path!("interrupt_manifest.txt")
    ssh_path = create_fake_ssh!(manifest_path)
    cli_path = write_script!(interrupt_script())

    assert {:ok, session} =
             HarnessDriver.start_session(
               provider: :codex,
               surface_kind: :leased_ssh,
               lease_ref: "lease-cancel",
               surface_ref: "surface-cancel",
               transport_options: [
                 ssh_path: ssh_path,
                 destination: "bridge.cancel.example"
               ]
             )

    on_exit(fn ->
      _ = HarnessDriver.stop_session(session)
    end)

    request = RunRequest.new!(%{prompt: "interrupt", metadata: %{}})
    parent = self()

    assert {:ok, %RunHandle{} = run, stream} =
             HarnessDriver.stream_run(session, request, cli_path: cli_path)

    task =
      Task.async(fn ->
        Enum.each(stream, fn event -> send(parent, {:bridge_event, event}) end)
      end)

    assert_receive {:bridge_event, %ExecutionEvent{type: :run_started}}, 2_000
    assert_eventually(fn -> File.exists?(manifest_path) end)
    assert :ok = HarnessDriver.cancel_run(session, run)

    assert_receive {:bridge_event,
                    %ExecutionEvent{type: :error, payload: %{"kind" => "user_cancelled"}}},
                   2_000

    assert :ok = Task.await(task, 2_000)
    assert_eventually(fn -> File.exists?(manifest_path) end)
    assert File.read!(manifest_path) =~ "destination=bridge.cancel.example"
  end

  test "run/3 maps failed leased SSHExec runs into failed execution results" do
    manifest_path = temp_path!("failed_manifest.txt")
    ssh_path = create_fake_ssh!(manifest_path)
    cli_path = write_script!(failing_script())

    assert {:ok, session} =
             HarnessDriver.start_session(
               provider: :codex,
               surface_kind: :leased_ssh,
               lease_ref: "lease-failed",
               surface_ref: "surface-failed",
               transport_options: [
                 ssh_path: ssh_path,
                 destination: "bridge.fail.example"
               ]
             )

    on_exit(fn ->
      _ = HarnessDriver.stop_session(session)
    end)

    request = RunRequest.new!(%{prompt: "fail", metadata: %{}})

    assert {:ok, %ExecutionResult{} = result} =
             HarnessDriver.run(session, request, cli_path: cli_path)

    assert result.status == :failed
    assert result.error["message"] =~ "CLI exited with code 42"
    assert result.error["kind"] == "unknown"
    assert result.error["domain"] == "runtime"
    assert_eventually(fn -> File.exists?(manifest_path) end)
    assert File.read!(manifest_path) =~ "destination=bridge.fail.example"
  end

  defp create_fake_ssh!(manifest_path) do
    dir = temp_dir!("fake_ssh")
    path = Path.join(dir, "ssh")

    File.write!(path, """
    #!/usr/bin/env bash
    set -euo pipefail

    destination=""
    port=""

    while [ "$#" -gt 0 ]; do
      case "$1" in
        -p)
          port="$2"
          shift 2
          ;;
        -o)
          shift 2
          ;;
        --)
          shift
          break
          ;;
        -*)
          shift
          ;;
        *)
          destination="$1"
          shift
          break
          ;;
      esac
    done

    remote_command="${1:-}"

    cat > "#{manifest_path}" <<EOF
    destination=${destination}
    port=${port}
    remote_command=${remote_command}
    EOF

    exec /bin/sh -lc "$remote_command"
    """)

    File.chmod!(path, 0o755)
    path
  end

  defp codex_success_script(text) do
    """
    #!/usr/bin/env bash
    set -euo pipefail
    echo '{"type":"thread.started","thread_id":"thread-1"}'
    echo '{"type":"turn.started"}'
    echo '{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"#{text}"}}'
    echo '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
    """
  end

  defp interrupt_script do
    """
    #!/usr/bin/env bash
    set -euo pipefail
    trap 'exit 130' INT
    while true; do
      sleep 0.1
    done
    """
  end

  defp failing_script do
    """
    #!/usr/bin/env bash
    set -euo pipefail
    echo 'ssh bridge stderr' >&2
    exit 42
    """
  end

  defp write_script!(contents) do
    path = Path.join(temp_dir!("script"), "fixture.sh")
    File.write!(path, contents)
    File.chmod!(path, 0o755)
    path
  end

  defp temp_path!(name) do
    Path.join(temp_dir!("tmp"), name)
  end

  defp temp_dir!(prefix) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "runtime_asm_bridge_ssh_exec_#{prefix}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)

    on_exit(fn ->
      File.rm_rf!(dir)
    end)

    dir
  end

  defp assert_eventually(fun, attempts \\ 40)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      assert true
    else
      Process.sleep(25)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(_fun, 0) do
    flunk("condition did not become true")
  end
end
