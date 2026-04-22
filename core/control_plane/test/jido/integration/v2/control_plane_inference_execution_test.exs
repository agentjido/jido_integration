defmodule Jido.Integration.V2.ControlPlaneInferenceExecutionTest do
  use ExUnit.Case

  alias ASM.ProviderBackend.{Event, Info}
  alias CliSubprocessCore.Event, as: CoreEvent
  alias CliSubprocessCore.Payload
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.ControlPlane.Inference.ReqLLMCallSpec
  alias Jido.Integration.V2.ControlPlane.TestSupport.FakeLlamaServerFixture
  alias Jido.Integration.V2.ControlPlane.TestSupport.FakeSelfHostedEndpointProvider
  alias Jido.Integration.V2.EndpointDescriptor
  alias Jido.Integration.V2.InferenceRequest

  @socket_capable? (case :gen_tcp.listen(0, [
                           :binary,
                           packet: :raw,
                           active: false,
                           reuseaddr: true
                         ]) do
                      {:ok, socket} ->
                        :ok = :gen_tcp.close(socket)
                        true

                      {:error, :eperm} ->
                        false

                      {:error, _reason} ->
                        true
                    end)

  defmodule OllamaReqHTTP do
  end

  defmodule FakeOllamaAttachFixture do
    defstruct [:pid, :root_url, :model_identity]

    @type t :: %__MODULE__{
            pid: pid(),
            root_url: String.t(),
            model_identity: String.t()
          }

    @spec start!(keyword()) :: t()
    def start!(opts \\ []) do
      model_identity = Keyword.get(opts, :model_identity, "llama3.2")

      {:ok, pid} =
        Agent.start_link(fn ->
          %{
            installed_models: Keyword.get(opts, :installed_models, [model_identity]),
            running_models: Keyword.get(opts, :running_models, [model_identity]),
            version: Keyword.get(opts, :version, "0.6.5"),
            response_text:
              Keyword.get(
                opts,
                :response_text,
                "Ollama attach proof is alive through req_llm."
              )
          }
        end)

      %__MODULE__{
        pid: pid,
        root_url:
          "http://ollama.control-plane.test/#{System.unique_integer([:positive, :monotonic])}",
        model_identity: model_identity
      }
    end

    @spec stop(t()) :: :ok
    def stop(%__MODULE__{} = fixture) do
      if Process.alive?(fixture.pid) do
        Agent.stop(fixture.pid, :normal)
      end

      :ok
    catch
      :exit, _reason -> :ok
    end

    @spec ollama_http(t()) ::
            (atom(), String.t(), map() | nil, keyword() ->
               {:ok, pos_integer(), map()} | {:error, term()})
    def ollama_http(%__MODULE__{} = fixture) do
      fn method, path, payload, _opts ->
        handle_ollama_http(fixture, method, path, payload)
      end
    end

    @spec req_http_options(t()) :: keyword()
    def req_http_options(%__MODULE__{} = fixture) do
      Req.Test.stub(OllamaReqHTTP, fn conn ->
        Req.Test.json(conn, chat_completion_payload(fixture))
      end)

      [plug: {Req.Test, OllamaReqHTTP}]
    end

    defp handle_ollama_http(%__MODULE__{pid: pid}, :get, "/api/version", _payload) do
      {:ok, 200, %{"version" => Agent.get(pid, & &1.version)}}
    end

    defp handle_ollama_http(%__MODULE__{pid: pid}, :get, "/api/ps", _payload) do
      running_models = Agent.get(pid, & &1.running_models)
      {:ok, 200, %{"models" => Enum.map(running_models, &%{"name" => &1})}}
    end

    defp handle_ollama_http(%__MODULE__{pid: pid}, :post, "/api/show", %{"model" => model}) do
      installed_models = Agent.get(pid, & &1.installed_models)

      if model in installed_models do
        {:ok, 200, %{"model" => model, "details" => %{"family" => "llama"}}}
      else
        {:ok, 404, %{"error" => "model not found"}}
      end
    end

    defp handle_ollama_http(_fixture, method, path, _payload) do
      {:error, {:unexpected_request, method, path}}
    end

    defp chat_completion_payload(%__MODULE__{pid: pid, model_identity: model_identity}) do
      %{
        "id" => "cmpl_inference_ollama_attach_123",
        "model" => model_identity,
        "choices" => [
          %{
            "finish_reason" => "stop",
            "message" => %{
              "role" => "assistant",
              "content" => Agent.get(pid, & &1.response_text)
            }
          }
        ],
        "usage" => %{
          "prompt_tokens" => 11,
          "completion_tokens" => 9,
          "total_tokens" => 20
        }
      }
    end
  end

  defmodule FakeCloudServerFixture do
    defstruct [:listener, :port, :response_body, :server_task]

    @type t :: %__MODULE__{
            listener: port(),
            port: pos_integer(),
            response_body: String.t(),
            server_task: pid()
          }

    @spec new!(map()) :: t()
    def new!(response_payload) when is_map(response_payload) do
      {:ok, listener} =
        :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

      {:ok, port} = :inet.port(listener)
      response_body = Jason.encode!(response_payload)

      {:ok, server_task} =
        Task.start_link(fn ->
          accept_loop(listener, response_body)
        end)

      %__MODULE__{
        listener: listener,
        port: port,
        response_body: response_body,
        server_task: server_task
      }
    end

    @spec base_url(t()) :: String.t()
    def base_url(%__MODULE__{port: port}), do: "http://127.0.0.1:#{port}/v1"

    @spec cleanup(t()) :: :ok
    def cleanup(%__MODULE__{} = fixture) do
      :ok = :gen_tcp.close(fixture.listener)
      Process.exit(fixture.server_task, :shutdown)
      :ok
    end

    defp accept_loop(listener, response_body) do
      case :gen_tcp.accept(listener) do
        {:ok, socket} ->
          :ok = recv_request(socket, "")
          :ok = :gen_tcp.send(socket, http_response(response_body))
          :ok = :gen_tcp.close(socket)
          accept_loop(listener, response_body)

        {:error, :closed} ->
          :ok
      end
    end

    defp recv_request(socket, buffer) do
      case :binary.match(buffer, "\r\n\r\n") do
        {headers_end, 4} ->
          headers = binary_part(buffer, 0, headers_end + 4)
          body = binary_part(buffer, headers_end + 4, byte_size(buffer) - headers_end - 4)
          content_length = content_length(headers)

          if byte_size(body) >= content_length do
            :ok
          else
            {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
            recv_request(socket, buffer <> chunk)
          end

        :nomatch ->
          {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
          recv_request(socket, buffer <> chunk)
      end
    end

    defp content_length(headers) do
      headers
      |> String.split("\r\n", trim: true)
      |> Enum.find_value(0, &content_length_line/1)
    end

    defp content_length_line(line) do
      case String.split(line, ":", parts: 2) do
        [name, value] -> parse_content_length(name, value)
        _other -> false
      end
    end

    defp parse_content_length(name, value) do
      case String.downcase(name) do
        "content-length" -> value |> String.trim() |> String.to_integer()
        _other -> false
      end
    end

    defp http_response(response_body) do
      [
        "HTTP/1.1 200 OK\r\n",
        "content-type: application/json\r\n",
        "content-length: ",
        Integer.to_string(byte_size(response_body)),
        "\r\n",
        "connection: close\r\n",
        "\r\n",
        response_body
      ]
    end
  end

  defmodule FakeASMBackend do
    use GenServer

    @behaviour ASM.ProviderBackend

    defstruct [:config, :subscriber, :subscription_ref]

    @impl true
    def start_run(config) when is_map(config) do
      with {:ok, pid} <- GenServer.start_link(__MODULE__, config) do
        {:ok, pid,
         Info.new(
           provider: config.provider.name,
           lane: Map.get(config, :lane, :core),
           backend: __MODULE__,
           runtime: __MODULE__,
           capabilities: [],
           session_pid: pid,
           raw_info: %{backend: :fake_asm, provider: config.provider.name}
         )}
      end
    end

    @impl true
    def send_input(_server, _input, _opts), do: :ok

    @impl true
    def end_input(_server), do: :ok

    @impl true
    def interrupt(_server), do: :ok

    @impl true
    def close(server) do
      GenServer.stop(server, :normal)
    catch
      :exit, _ -> :ok
    end

    @impl true
    def subscribe(server, pid, ref) do
      GenServer.call(server, {:subscribe, pid, ref})
    end

    @impl true
    def info(server) do
      GenServer.call(server, :info)
    end

    @impl true
    def init(config) do
      {:ok, %__MODULE__{config: config, subscriber: nil, subscription_ref: nil}}
    end

    @impl true
    def handle_call({:subscribe, pid, ref}, _from, state) do
      state = %{state | subscriber: pid, subscription_ref: ref}
      emit_script(state)
      {:reply, :ok, state}
    end

    def handle_call(:info, _from, state) do
      {:reply,
       Info.new(
         provider: state.config.provider.name,
         lane: Map.get(state.config, :lane, :core),
         backend: __MODULE__,
         runtime: __MODULE__,
         capabilities: [],
         session_pid: self(),
         raw_info: %{backend: :fake_asm, provider: state.config.provider.name}
       ), state}
    end

    defp emit_script(%__MODULE__{} = state) do
      state.config.backend_opts
      |> Keyword.get(:script, [])
      |> Enum.each(fn {kind, payload} ->
        send(
          state.subscriber,
          Event.new(
            state.subscription_ref,
            CoreEvent.new(kind, provider: state.config.provider.name, payload: payload)
          )
        )
      end)
    end
  end

  setup do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
    ControlPlane.reset!()
    original_asm_endpoint = Application.get_env(:agent_session_manager, ASM.InferenceEndpoint)

    original_self_hosted_provider =
      Application.get_env(:jido_integration_v2_control_plane, :self_hosted_endpoint_provider)

    Application.put_env(
      :jido_integration_v2_control_plane,
      :self_hosted_endpoint_provider,
      FakeSelfHostedEndpointProvider
    )

    on_exit(fn ->
      FakeSelfHostedEndpointProvider.cleanup!()

      if is_nil(original_asm_endpoint) do
        Application.delete_env(:agent_session_manager, ASM.InferenceEndpoint)
      else
        Application.put_env(:agent_session_manager, ASM.InferenceEndpoint, original_asm_endpoint)
      end

      if is_nil(original_self_hosted_provider) do
        Application.delete_env(
          :jido_integration_v2_control_plane,
          :self_hosted_endpoint_provider
        )
      else
        Application.put_env(
          :jido_integration_v2_control_plane,
          :self_hosted_endpoint_provider,
          original_self_hosted_provider
        )
      end
    end)

    :ok
  end

  test "invoke_inference/2 rejects missing descriptor refs when required by a touched path" do
    request =
      InferenceRequest.new!(%{
        request_id: "req-missing-descriptor-refs-1",
        operation: :generate_text,
        messages: [%{role: "user", content: "Require the M8 descriptor guard"}],
        prompt: nil,
        model_preference: %{provider: "openai", id: "gpt-local"},
        target_preference: %{target_class: "cloud_provider"},
        stream?: false,
        tool_policy: %{},
        output_constraints: %{},
        metadata: %{tenant_id: "tenant-missing-descriptor-refs-1"}
      })

    assert {:error, {:missing_required_inference_descriptor_refs, missing}} =
             ControlPlane.invoke_inference(
               request,
               run_id: "run-missing-descriptor-refs-1",
               trace_id: "trace-missing-descriptor-refs-1",
               require_descriptor_refs?: true
             )

    assert Enum.sort(missing) == ["endpoint_id", "model_identity", "model_version"]
  end

  test "builds an endpoint-shaped ReqLLM call spec from an endpoint descriptor" do
    request =
      InferenceRequest.new!(%{
        request_id: "req-call-spec-endpoint-1",
        operation: :stream_text,
        messages: [%{role: "user", content: "Stream from the local endpoint"}],
        prompt: nil,
        model_preference: %{provider: "openai", id: "ignored-on-endpoint"},
        target_preference: %{target_class: "self_hosted_endpoint"},
        stream?: true,
        tool_policy: %{},
        output_constraints: %{temperature: 0.1},
        metadata: %{}
      })

    endpoint =
      EndpointDescriptor.new!(%{
        endpoint_id: "endpoint-call-spec-1",
        runtime_kind: :service,
        management_mode: :jido_managed,
        target_class: :self_hosted_endpoint,
        protocol: :openai_chat_completions,
        base_url: "http://127.0.0.1:8080/v1",
        headers: %{
          "authorization" => "Bearer local-token",
          "x-jido-route" => "inference"
        },
        provider_identity: :llama_cpp_sdk,
        model_identity: "llama-3.2-3b-instruct",
        source_runtime: :llama_cpp_sdk,
        source_runtime_ref: "llama-runtime-1",
        lease_ref: "lease-call-spec-1",
        health_ref: "health-call-spec-1",
        boundary_ref: "boundary-call-spec-1",
        capabilities: %{streaming?: true},
        metadata: %{}
      })

    call_spec =
      ReqLLMCallSpec.from_endpoint(
        request,
        %{
          run_id: "run-call-spec-endpoint-1",
          attempt_id: "run-call-spec-endpoint-1:1",
          observability: %{trace_id: "trace-call-spec-endpoint-1"}
        },
        endpoint
      )

    assert call_spec.operation == :stream_text
    assert call_spec.model_spec.provider == :openai
    assert call_spec.model_spec.id == "llama-3.2-3b-instruct"
    assert call_spec.base_url == "http://127.0.0.1:8080/v1"
    assert call_spec.headers == %{"x-jido-route" => "inference"}
    assert call_spec.options == %{api_key: "local-token", temperature: 0.1}
    assert call_spec.observability == %{trace_id: "trace-call-spec-endpoint-1"}
  end

  @tag skip:
         not @socket_capable? and
           "requires a socket-capable environment for the cloud proof"
  test "invoke_inference/2 records durable cloud execution truth through req_llm" do
    cloud_fixture =
      FakeCloudServerFixture.new!(%{
        "id" => "cmpl_inference_cloud_123",
        "model" => "gpt-4o-mini",
        "choices" => [
          %{
            "finish_reason" => "stop",
            "message" => %{
              "role" => "assistant",
              "content" => "Phase 4 cloud path is alive."
            }
          }
        ],
        "usage" => %{
          "prompt_tokens" => 12,
          "completion_tokens" => 7,
          "total_tokens" => 19
        }
      })

    on_exit(fn -> FakeCloudServerFixture.cleanup(cloud_fixture) end)

    request =
      InferenceRequest.new!(%{
        request_id: "req-live-cloud-1",
        operation: :generate_text,
        messages: [%{role: "user", content: "Summarize phase 4"}],
        prompt: nil,
        model_preference: %{
          provider: "openai",
          id: "gpt-4o-mini",
          base_url: FakeCloudServerFixture.base_url(cloud_fixture)
        },
        target_preference: %{target_class: "cloud_provider"},
        stream?: false,
        tool_policy: %{},
        output_constraints: %{},
        metadata: %{tenant_id: "tenant-live-cloud-1"}
      })

    assert {:ok, result} =
             ControlPlane.invoke_inference(
               request,
               api_key: "cloud-fixture-token",
               run_id: "run-live-cloud-1",
               decision_ref: "decision-live-cloud-1",
               trace_id: "trace-live-cloud-1"
             )

    assert result.inference_result.status == :ok
    assert result.inference_result.finish_reason == :stop
    assert result.compatibility_result.metadata.route == :cloud
    assert result.endpoint_descriptor == nil
    assert result.backend_manifest == nil

    assert Enum.map(ControlPlane.events(result.run.run_id), & &1.type) == [
             "inference.request_admitted",
             "inference.attempt_started",
             "inference.compatibility_evaluated",
             "inference.target_resolved",
             "inference.attempt_completed"
           ]

    assert {:ok, attempt} = ControlPlane.fetch_attempt(result.attempt.attempt_id)
    assert attempt.output["inference_result"]["status"] == "ok"
    assert attempt.output["compatibility_result"]["metadata"]["route"] == "cloud"
  end

  @tag skip:
         not @socket_capable? and
           "requires a socket-capable environment for the ASM endpoint proof"
  test "invoke_inference/2 records durable CLI streaming truth through an ASM endpoint" do
    configure_asm_endpoint("ASM CLI proof is alive.")

    request =
      InferenceRequest.new!(%{
        request_id: "req-live-cli-1",
        operation: :stream_text,
        messages: [%{role: "user", content: "Stream through ASM.InferenceEndpoint"}],
        prompt: nil,
        model_preference: %{provider: "gemini", id: "gemini-2.5-pro"},
        target_preference: %{target_class: "cli_endpoint"},
        stream?: true,
        tool_policy: %{},
        output_constraints: %{},
        metadata: %{tenant_id: "tenant-live-cli-1"}
      })

    assert {:ok, result} =
             ControlPlane.invoke_inference(
               request,
               run_id: "run-live-cli-1",
               decision_ref: "decision-live-cli-1",
               trace_id: "trace-live-cli-1",
               ttl_ms: 5_000
             )

    assert result.response_text == "ASM CLI proof is alive."
    assert result.inference_result.status == :ok
    assert result.inference_result.streaming?
    assert result.compatibility_result.metadata.route == :cli
    assert result.endpoint_descriptor.target_class == :cli_endpoint
    assert result.endpoint_descriptor.source_runtime == :agent_session_manager
    assert result.backend_manifest.backend == :asm_inference_endpoint
    assert result.backend_manifest.capabilities.tool_calling? == false
    assert result.lease_ref.lease_ref == result.endpoint_descriptor.lease_ref

    assert Enum.map(ControlPlane.events(result.run.run_id), & &1.type) == [
             "inference.request_admitted",
             "inference.attempt_started",
             "inference.compatibility_evaluated",
             "inference.target_resolved",
             "inference.stream_opened",
             "inference.stream_checkpoint",
             "inference.stream_closed",
             "inference.attempt_completed"
           ]

    assert {:ok, attempt} = ControlPlane.fetch_attempt(result.attempt.attempt_id)
    assert attempt.output["endpoint_descriptor"]["source_runtime"] == "agent_session_manager"
    assert attempt.output["compatibility_result"]["metadata"]["route"] == "cli"
    assert attempt.output["backend_manifest"]["backend"] == "asm_inference_endpoint"
  end

  @tag skip:
         not @socket_capable? and
           "requires a socket-capable environment for llama_cpp_sdk endpoint proof"
  test "invoke_inference/2 records durable self-hosted streaming truth through a llama.cpp endpoint" do
    fixture = FakeLlamaServerFixture.new!()

    on_exit(fn ->
      FakeLlamaServerFixture.cleanup(fixture)
    end)

    request =
      InferenceRequest.new!(%{
        request_id: "req-live-self-hosted-1",
        operation: :stream_text,
        messages: [%{role: "user", content: "Stream the self-hosted phase 4 proof"}],
        prompt: nil,
        model_preference: %{provider: "openai", id: "fixture-llama"},
        target_preference: %{
          target_class: "self_hosted_endpoint",
          backend: "llama_cpp_sdk",
          boot_spec:
            FakeLlamaServerFixture.boot_spec(
              fixture,
              alias: "fixture-llama",
              api_key: "fixture-token",
              api_prefix: "/managed"
            )
        },
        stream?: true,
        tool_policy: %{},
        output_constraints: %{temperature: 0.1},
        metadata: %{tenant_id: "tenant-live-self-hosted-1"}
      })

    assert {:ok, result} =
             ControlPlane.invoke_inference(
               request,
               run_id: "run-live-self-hosted-1",
               decision_ref: "decision-live-self-hosted-1",
               trace_id: "trace-live-self-hosted-1",
               ttl_ms: 5_000
             )

    assert result.inference_result.status == :ok
    assert result.inference_result.streaming?
    assert result.inference_result.finish_reason == :stop
    assert result.compatibility_result.metadata.route == :self_hosted
    assert result.endpoint_descriptor.target_class == :self_hosted_endpoint
    assert result.endpoint_descriptor.base_url == "http://127.0.0.1:#{fixture.port}/managed/v1"
    assert result.backend_manifest.backend == :llama_cpp_sdk
    assert result.lease_ref.lease_ref == result.endpoint_descriptor.lease_ref
    assert result.stream.opened.checkpoint_policy == :summary
    assert result.stream.closed.chunk_count > 0
    assert result.stream.closed.byte_count > 0

    assert Enum.map(ControlPlane.events(result.run.run_id), & &1.type) == [
             "inference.request_admitted",
             "inference.attempt_started",
             "inference.compatibility_evaluated",
             "inference.target_resolved",
             "inference.stream_opened",
             "inference.stream_checkpoint",
             "inference.stream_closed",
             "inference.attempt_completed"
           ]

    assert {:ok, attempt} = ControlPlane.fetch_attempt(result.attempt.attempt_id)
    assert attempt.output["endpoint_descriptor"]["provider_identity"] == "llama_cpp_sdk"
    assert attempt.output["compatibility_result"]["metadata"]["route"] == "self_hosted"
    assert attempt.output["lease_ref"]["lease_ref"] == result.lease_ref.lease_ref
  end

  test "invoke_inference/2 records durable attached-local truth through an ollama endpoint" do
    fixture =
      FakeOllamaAttachFixture.start!(
        model_identity: "llama3.2",
        response_text: "Ollama attach proof is alive through req_llm."
      )

    on_exit(fn ->
      FakeOllamaAttachFixture.stop(fixture)
    end)

    request =
      InferenceRequest.new!(%{
        request_id: "req-live-ollama-attach-1",
        operation: :generate_text,
        messages: [%{role: "user", content: "Summarize the attached local proof"}],
        prompt: nil,
        model_preference: %{provider: "openai", id: fixture.model_identity},
        target_preference: %{
          target_class: "self_hosted_endpoint",
          backend: "ollama",
          backend_options: %{
            root_url: fixture.root_url,
            ollama_http: FakeOllamaAttachFixture.ollama_http(fixture)
          }
        },
        stream?: false,
        tool_policy: %{},
        output_constraints: %{temperature: 0.1},
        metadata: %{tenant_id: "tenant-live-ollama-attach-1"}
      })

    assert {:ok, result} =
             ControlPlane.invoke_inference(
               request,
               run_id: "run-live-ollama-attach-1",
               decision_ref: "decision-live-ollama-attach-1",
               trace_id: "trace-live-ollama-attach-1",
               ttl_ms: 5_000,
               require_descriptor_refs?: true,
               req_http_options: FakeOllamaAttachFixture.req_http_options(fixture)
             )

    assert result.response_text == "Ollama attach proof is alive through req_llm."
    assert result.inference_result.status == :ok
    assert result.inference_result.streaming? == false
    assert result.compatibility_result.metadata.route == :self_hosted
    assert result.compatibility_result.resolved_management_mode == :externally_managed
    assert result.endpoint_descriptor.target_class == :self_hosted_endpoint
    assert result.endpoint_descriptor.management_mode == :externally_managed
    assert result.endpoint_descriptor.provider_identity == :ollama
    assert result.endpoint_descriptor.base_url == fixture.root_url <> "/v1"
    assert result.backend_manifest.backend == :ollama
    assert result.lease_ref.lease_ref == result.endpoint_descriptor.lease_ref

    assert Enum.map(ControlPlane.events(result.run.run_id), & &1.type) == [
             "inference.request_admitted",
             "inference.attempt_started",
             "inference.compatibility_evaluated",
             "inference.target_resolved",
             "inference.attempt_completed"
           ]

    assert {:ok, attempt} = ControlPlane.fetch_attempt(result.attempt.attempt_id)
    assert attempt.output["endpoint_descriptor"]["provider_identity"] == "ollama"
    assert attempt.output["endpoint_descriptor"]["metadata"]["model_version"] == "v1"
    assert attempt.output["endpoint_descriptor"]["management_mode"] == "externally_managed"
    assert attempt.output["backend_manifest"]["backend"] == "ollama"

    assert attempt.output["compatibility_result"]["resolved_management_mode"] ==
             "externally_managed"
  end

  defp configure_asm_endpoint(text) do
    Application.put_env(
      :agent_session_manager,
      ASM.InferenceEndpoint,
      backend_module: FakeASMBackend,
      backend_opts: [
        script: [
          {:run_started, Payload.RunStarted.new(command: "fake", args: ["prompt"], cwd: "/tmp")},
          {:assistant_delta, Payload.AssistantDelta.new(content: text)},
          {:result, Payload.Result.new(status: :completed, stop_reason: :end_turn)}
        ]
      ]
    )
  end
end
