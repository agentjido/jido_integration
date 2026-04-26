defmodule LiveCodexAppServerAcceptance do
  @moduledoc false

  alias Jido.Integration.V2.AsmRuntimeBridge.RuntimeControlDriver
  alias Jido.RuntimeControl
  alias Jido.RuntimeControl.RunRequest

  @marker "JIDO_CODEX_APP_SERVER_OK_20260425"
  @tool_marker "JIDO_CODEX_HOST_TOOL_OK_20260425"

  def run do
    cwd = parse_cwd(System.argv())

    load_codex_sdk!()
    start_runtime!()

    tool_spec = %{
      "name" => "echo_json",
      "description" => "Echoes the JSON object supplied by the model.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "message" => %{"type" => "string"}
        },
        "required" => ["message"],
        "additionalProperties" => true
      }
    }

    request =
      RunRequest.new!(%{
        prompt:
          "Call echo_json once with message #{@tool_marker}. After the tool returns, reply exactly #{@marker}.",
        host_tools: [tool_spec],
        provider_metadata: %{app_server: true},
        metadata: %{}
      })

    tools = %{
      "echo_json" => fn args ->
        {:ok, %{"marker" => @tool_marker, "echo" => args}}
      end
    }

    {:ok, session} =
      RuntimeControl.start_session(:asm,
        provider: :codex,
        lane: :sdk,
        cwd: cwd,
        permission_mode: :bypass,
        stream_timeout_ms: 120_000,
        backend_opts: [run_opts: [timeout_ms: 120_000]]
      )

    try do
      {:ok, status} = RuntimeControl.session_status(session)
      assert_control_status!(status, session)

      {:ok, _run, stream} =
        RuntimeControl.stream_run(session, request,
          lane: :sdk,
          app_server: true,
          tools: tools,
          cwd: cwd,
          permission_mode: :bypass,
          stream_timeout_ms: 120_000,
          backend_opts: [run_opts: [timeout_ms: 120_000]],
          run_id: "jido-codex-app-server-live-#{System.unique_integer([:positive])}"
        )

      events = Enum.to_list(stream)
      assert_live_result!(events)
    after
      _ = RuntimeControl.stop_session(session)
    end
  end

  defp assert_control_status!(status, session) do
    unless status.session_id == session.session_id and status.state == :ready do
      raise "live acceptance failed: session status was not ready; got #{inspect(status)}"
    end
  end

  defp assert_live_result!(events) do
    provider_session_id =
      events
      |> Enum.map(& &1.provider_session_id)
      |> Enum.find(&present?/1)

    host_tool_requested? = Enum.any?(events, &(&1.type == :host_tool_requested))
    host_tool_completed? = Enum.any?(events, &(&1.type == :host_tool_completed))
    text = streamed_text(events)

    unless present?(provider_session_id) do
      raise "live acceptance failed: missing provider_session_id in Runtime Control events"
    end

    unless host_tool_requested? and host_tool_completed? do
      raise "live acceptance failed: host tool request/completion events were not observed"
    end

    unless String.contains?(text, @marker) do
      raise "live acceptance failed: response text did not contain #{@marker}; got #{inspect(text)}"
    end

    IO.puts("jido_codex_app_server_live=ok")
    IO.puts("provider_session_id=#{provider_session_id}")
    IO.puts("session_control_status=ready")
    IO.puts("host_tool_events=requested,completed")
    IO.puts("text=#{String.trim(text)}")
  end

  defp streamed_text(events) do
    events
    |> Enum.map(fn event ->
      case event.payload do
        %{"content" => content} when is_binary(content) -> content
        %{"text" => text} when is_binary(text) -> text
        _other -> ""
      end
    end)
    |> Enum.join()
  end

  defp start_runtime! do
    Application.put_env(:jido_runtime_control, :runtime_drivers, %{asm: RuntimeControlDriver})
    Application.put_env(:jido_runtime_control, :default_runtime_driver, :asm)

    {:ok, _apps} = Application.ensure_all_started(:agent_session_manager)
    start_once!(Jido.Integration.V2.AsmRuntimeBridge.Application)
    :ok
  end

  defp start_once!(module) do
    case module.start(:normal, []) do
      {:ok, pid} ->
        Process.unlink(pid)
        :ok

      {:error, {:already_started, _pid}} ->
        :ok
    end
  end

  defp load_codex_sdk! do
    codex_sdk_path =
      __DIR__
      |> Path.expand()
      |> Path.join("../../../../codex_sdk")
      |> Path.expand()

    unless File.dir?(codex_sdk_path) do
      raise "live acceptance failed: codex_sdk sibling repo not found at #{codex_sdk_path}"
    end

    {_, 0} =
      System.cmd("mix", ["compile"],
        cd: codex_sdk_path,
        into: IO.stream(:stdio, :line)
      )

    codex_sdk_path
    |> Path.join("_build/dev/lib/*/ebin")
    |> Path.wildcard()
    |> Enum.each(&Code.prepend_path(String.to_charlist(&1)))

    case Application.ensure_all_started(:codex_sdk) do
      {:ok, _apps} -> :ok
      {:error, reason} -> raise "live acceptance failed: cannot start codex_sdk: #{inspect(reason)}"
    end

    unless Code.ensure_loaded?(Codex.AppServer) do
      raise "live acceptance failed: Codex.AppServer is unavailable"
    end
  end

  defp parse_cwd(argv) do
    case argv do
      ["--cwd", cwd | _rest] -> cwd
      _other -> Path.expand("../../..", __DIR__)
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end

LiveCodexAppServerAcceptance.run()
