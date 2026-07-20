defmodule Jido.Integration.V2.ControlPlaneInferenceExecutionTest do
  use ExUnit.Case

  alias ASM.ProviderBackend.{Event, Info}
  alias ASM.InferenceEndpoint.RuntimeConfig, as: ASMRuntimeConfig
  alias CliSubprocessCore.Event, as: CoreEvent
  alias CliSubprocessCore.Payload
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.ManagedAccount
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.ControlPlane.Inference.CallPlan
  alias Jido.Integration.V2.ControlPlane.RuntimeConfig
  alias Jido.Integration.V2.ControlPlane.TestSupport.FakeLlamaServerFixture
  alias Jido.Integration.V2.ControlPlane.TestSupport.FakeSelfHostedEndpointProvider
  alias Jido.Integration.V2.EndpointDescriptor
  alias Jido.Integration.V2.InferenceRequest
  alias Jido.Integration.V2.MaterializationRequest

  @control_plane_store_keys [
    :run_store,
    :attempt_store,
    :event_store,
    :artifact_store,
    :claim_check_store,
    :target_store,
    :ingress_store,
    :profile_registry_store
  ]

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
    def new!(response_payload, owner \\ self()) when is_map(response_payload) do
      {:ok, listener} =
        :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

      {:ok, port} = :inet.port(listener)
      response_body = Jason.encode!(response_payload)

      {:ok, server_task} =
        Task.start_link(fn ->
          accept_loop(listener, response_body, owner)
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

    defp accept_loop(listener, response_body, owner) do
      case :gen_tcp.accept(listener) do
        {:ok, socket} ->
          {:ok, request} = recv_request(socket, "")
          send(owner, {:cloud_request, request})
          :ok = :gen_tcp.send(socket, http_response(response_body))
          :ok = :gen_tcp.close(socket)
          accept_loop(listener, response_body, owner)

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
            {:ok, buffer}
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

  defmodule ManagedStore do
    @behaviour Jido.Integration.V2.Auth.ManagedAccountStore

    use Agent

    def start_link(_opts),
      do: Agent.start_link(fn -> %{accounts: %{}, versions: %{}} end, name: __MODULE__)

    @impl true
    def transact(fun), do: fun.()

    @impl true
    def register(account, version) do
      Agent.update(__MODULE__, fn state ->
        state
        |> put_in([:accounts, account.account_ref], account)
        |> put_in([:versions, {account.account_ref, version.generation}], version)
      end)
    end

    @impl true
    def fetch(account_ref) do
      Agent.get(__MODULE__, fn state ->
        case Map.get(state.accounts, account_ref) do
          nil -> {:error, :unknown_managed_account}
          account -> {:ok, account}
        end
      end)
    end

    @impl true
    def lock(account_ref), do: fetch(account_ref)

    @impl true
    def fetch_by_connection(connection_id) do
      Agent.get(__MODULE__, fn state ->
        case Enum.find(Map.values(state.accounts), &(&1.connection_id == connection_id)) do
          nil -> {:error, :unknown_managed_account}
          account -> {:ok, account}
        end
      end)
    end

    @impl true
    def fetch_version(account_ref, generation) do
      Agent.get(__MODULE__, fn state ->
        case Map.get(state.versions, {account_ref, generation}) do
          nil -> {:error, :unknown_credential_generation}
          version -> {:ok, version}
        end
      end)
    end

    @impl true
    def rotate(_account_ref, _expected_generation, _fence, _version, _now),
      do: {:error, :unsupported_in_test_store}

    @impl true
    def revoke(_account_ref, _generation, _fence, _revocation_ref, _now),
      do: {:error, :unsupported_in_test_store}
  end

  defmodule ManagedMaterializer do
    @behaviour Jido.Integration.V2.CredentialMaterializer

    @impl true
    def materialize(_lease, request) do
      Jido.Integration.V2.SecretMaterial.new(%{
        materialization_ref: request.materialization_ref,
        provider_family: request.account.provider_family,
        account_ref: request.account.account_ref,
        generation: request.account.generation,
        payload: %{api_key: "managed-cloud-sentinel"}
      })
    end

    @impl true
    def revoke(_material, _opts), do: :ok
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
    previous_store_env = snapshot_control_plane_store_env()
    reset_control_plane_store_env()
    ControlPlane.reset!()
    original_asm_runtime_config = ASMRuntimeConfig.current()
    :ok = ASMRuntimeConfig.reset()
    original_runtime_config = RuntimeConfig.current()
    :ok = RuntimeConfig.put(:self_hosted_endpoint_provider, FakeSelfHostedEndpointProvider)

    on_exit(fn ->
      FakeSelfHostedEndpointProvider.cleanup!()
      restore_control_plane_store_env(previous_store_env)
      :ok = ASMRuntimeConfig.reset()
      :ok = ASMRuntimeConfig.configure!(original_asm_runtime_config)
      :ok = RuntimeConfig.reset()
      restore_runtime_config(original_runtime_config)
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

  test "invoke_inference/2 rejects raw prompt recording without artifact refs when required" do
    request =
      InferenceRequest.new!(%{
        request_id: "req-missing-prompt-artifact-ref-1",
        operation: :generate_text,
        messages: [%{role: "user", content: "Require the M8 artifact boundary"}],
        prompt: nil,
        model_preference: %{provider: "openai", id: "gpt-local"},
        target_preference: %{target_class: "cloud_provider"},
        stream?: false,
        tool_policy: %{},
        output_constraints: %{},
        metadata: %{tenant_id: "tenant-missing-prompt-artifact-ref-1"}
      })

    assert {:error, {:missing_required_artifact_ref, :prompt_or_messages}} =
             ControlPlane.invoke_inference(
               request,
               run_id: "run-missing-prompt-artifact-ref-1",
               trace_id: "trace-missing-prompt-artifact-ref-1",
               require_artifact_refs?: true
             )
  end

  test "invoke_inference/2 rejects raw credential supplementation on a managed route" do
    request =
      InferenceRequest.new!(%{
        request_id: "req-managed-secret-guard-1",
        operation: :generate_text,
        messages: [%{role: "user", content: "Use only an admitted managed credential"}],
        prompt: nil,
        model_preference: %{provider: "gemini", id: "gemini-2.5-flash"},
        target_preference: %{
          target_class: "cloud_provider",
          management_mode: :jido_managed
        },
        stream?: false,
        tool_policy: %{},
        output_constraints: %{},
        metadata: %{tenant_id: "tenant-managed-secret-guard-1"}
      })

    assert {:error, {:secret_material_forbidden, [:api_key]}} =
             ControlPlane.invoke_inference(request,
               api_key: "managed-route-option-sentinel"
             )

    assert {:error,
            {:secret_material_forbidden, [:target_backend_options, :headers, :authorization]}} =
             ControlPlane.invoke_inference(request,
               target_backend_options: %{
                 headers: %{authorization: "Bearer managed-route-request-sentinel"}
               }
             )

    assert {:error, {:managed_credential_materialization_required, :credential_lease}} =
             ControlPlane.invoke_inference(request)
  end

  test "keeps explicit standalone endpoint authorization out of durable request options" do
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
        management_mode: :externally_managed,
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

    call_plan =
      CallPlan.from_endpoint(
        request,
        %{
          run_id: "run-call-spec-endpoint-1",
          attempt_id: "run-call-spec-endpoint-1:1",
          observability: %{trace_id: "trace-call-spec-endpoint-1"}
        },
        endpoint
      )

    assert call_plan.operation == :stream_text
    assert call_plan.model_spec.provider == :openai
    assert call_plan.model_spec.id == "llama-3.2-3b-instruct"
    assert call_plan.base_url == "http://127.0.0.1:8080/v1"

    assert call_plan.headers == %{"x-jido-route" => "inference"}
    assert call_plan.standalone_api_key == "local-token"

    assert call_plan.options == %{temperature: 0.1}
    refute Map.has_key?(call_plan.options, :api_key)
    assert call_plan.observability == %{trace_id: "trace-call-spec-endpoint-1"}
    refute inspect(call_plan) =~ "local-token"
    refute inspect(call_plan) =~ "authorization"
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
           "requires a socket-capable environment for the managed cloud proof"
  test "managed inference materializes inside the bounded Auth effect and records only lease truth" do
    start_supervised!(ManagedStore)
    Auth.reset!()

    Auth.configure_managed_accounts!(
      store: ManagedStore,
      materializers: %{"openai" => ManagedMaterializer}
    )

    on_exit(fn -> Auth.reset!() end)

    cloud_fixture =
      FakeCloudServerFixture.new!(%{
        "id" => "cmpl_managed_cloud_123",
        "model" => "gpt-4o-mini",
        "choices" => [
          %{
            "finish_reason" => "stop",
            "message" => %{
              "role" => "assistant",
              "content" => "Managed materialization stayed inside the effect task."
            }
          }
        ],
        "usage" => %{
          "prompt_tokens" => 8,
          "completion_tokens" => 8,
          "total_tokens" => 16
        }
      })

    on_exit(fn -> FakeCloudServerFixture.cleanup(cloud_fixture) end)

    now = ~U[2026-07-20 12:00:00Z]

    assert {:ok, %{account: account, account_ref: account_ref}} =
             Auth.register_managed_account(managed_registration(now))

    lease_context = managed_lease_context(account, now)
    assert {:ok, lease} = Auth.request_managed_lease(account_ref, lease_context)

    materialization_request =
      MaterializationRequest.new!(%{
        materialization_ref: "materialization://openai/control-plane/1",
        lease_id: lease.lease_id,
        account: account_ref,
        effect_ref: lease_context.effect_ref,
        operation_ref: lease_context.operation_ref,
        authority_ref: lease_context.authority_ref,
        endpoint_ref: account.endpoint_ref,
        target_ref: lease_context.target_ref,
        issued_at: DateTime.add(now, 1, :second),
        expires_at: DateTime.add(now, 30, :second)
      })

    request =
      InferenceRequest.new!(%{
        request_id: "req-managed-cloud-1",
        operation: :generate_text,
        messages: [%{role: "user", content: "Use the bounded managed account"}],
        prompt: nil,
        model_preference: %{
          provider: "openai",
          id: "gpt-4o-mini",
          base_url: FakeCloudServerFixture.base_url(cloud_fixture)
        },
        target_preference: %{
          target_class: "cloud_provider",
          management_mode: :jido_managed
        },
        stream?: false,
        tool_policy: %{},
        output_constraints: %{},
        metadata: %{tenant_id: account.tenant_id}
      })

    assert {:ok, result} =
             ControlPlane.invoke_inference(request,
               credential_lease: lease,
               materialization_request: materialization_request,
               materialization_context: managed_redemption_context(lease_context, now),
               run_id: "run-managed-cloud-1",
               decision_ref: "decision-managed-cloud-1",
               trace_id: "trace-managed-cloud-1"
             )

    assert result.compatibility_result.resolved_management_mode == :jido_managed
    assert result.credential_lease_id == lease.lease_id
    assert result.attempt.credential_lease_id == lease.lease_id
    refute inspect(result) =~ "managed-cloud-sentinel"

    assert_receive {:cloud_request, raw_request}

    assert raw_request
           |> String.downcase()
           |> String.contains?("authorization: bearer managed-cloud-sentinel")

    assert {:ok, stored_attempt} = ControlPlane.fetch_attempt(result.attempt.attempt_id)
    refute inspect(stored_attempt) =~ "managed-cloud-sentinel"

    assert {:ok, fetched_lease} =
             Auth.fetch_lease(lease.lease_id, %{tenant_id: account.tenant_id, now: now})

    assert fetched_lease.payload == %{}
    assert fetched_lease.metadata.redemption_count == 1

    assert fetched_lease.metadata.last_materialization_ref ==
             materialization_request.materialization_ref
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
        model_preference: %{provider: "claude", id: "sonnet"},
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

    [server_pid] = FakeSelfHostedEndpointProvider.active_server_os_pids()
    assert FakeSelfHostedEndpointProvider.os_pid_alive?(server_pid)

    FakeSelfHostedEndpointProvider.cleanup!()
    refute FakeSelfHostedEndpointProvider.os_pid_alive?(server_pid)
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
        metadata: %{
          tenant_id: "tenant-live-ollama-attach-1",
          prompt_artifact_ref: "artifact://phase5/m8/ollama-attach-prompt"
        }
      })

    assert {:ok, result} =
             ControlPlane.invoke_inference(
               request,
               run_id: "run-live-ollama-attach-1",
               decision_ref: "decision-live-ollama-attach-1",
               trace_id: "trace-live-ollama-attach-1",
               ttl_ms: 5_000,
               require_descriptor_refs?: true,
               require_artifact_refs?: true,
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
    assert {:ok, run} = ControlPlane.fetch_run(result.run.run_id)

    assert run.input["request"]["messages"] == []
    assert run.input["request"]["prompt"] == nil

    assert run.input["request"]["metadata"]["prompt_artifact_ref"] ==
             "artifact://phase5/m8/ollama-attach-prompt"

    assert attempt.output["endpoint_descriptor"]["provider_identity"] == "ollama"
    assert attempt.output["endpoint_descriptor"]["metadata"]["model_version"] == "v1"
    assert attempt.output["endpoint_descriptor"]["management_mode"] == "externally_managed"
    assert attempt.output["backend_manifest"]["backend"] == "ollama"
    refute Map.has_key?(attempt.output["inference_result"]["metadata"], "text")

    assert sha256_ref?(
             attempt.output["inference_result"]["metadata"]["text_artifact_ref"]["content_hash"]
           )

    assert attempt.output["compatibility_result"]["resolved_management_mode"] ==
             "externally_managed"
  end

  defp managed_registration(now) do
    %{
      provider_family: "openai",
      account_ref: "provider-account://tenant-managed/openai/account-a",
      tenant_id: "tenant-managed",
      connector_id: "openai",
      endpoint_ref: "endpoint://openai/chat-completions",
      quota_scope_ref: "quota://openai/account-a",
      credential_handle_ref: "credential-handle://openai/account-a/v1",
      secret_provider_ref: "vault://nshkr/kv-v2",
      secret_binding_ref: "vault-secret://openai/account-a/v1",
      subject: "nshkr-runtime",
      actor_id: "operator-1",
      scopes: ["model:invoke"],
      lease_fields: ["api_key"],
      now: now
    }
  end

  defp managed_lease_context(%ManagedAccount{} = account, now) do
    %{
      tenant_id: account.tenant_id,
      actor_id: "runtime-1",
      required_scopes: ["model:invoke"],
      ttl_seconds: 60,
      now: now,
      provider_family: account.provider_family,
      provider_account_ref: account.account_ref,
      connector_instance_ref: "connector-instance://openai/primary",
      credential_handle_ref: account.credential_handle_ref,
      operation_class: "inference",
      execution_context_ref: "execution-context://run/managed-cloud-1",
      target_ref: "target://openai/cloud",
      attach_grant_ref: "attach-grant://openai/1",
      operation_policy_ref: "operation-policy://openai/generate",
      policy_revision_ref: "policy-revision://openai/1",
      target_grant_revision: "target-grant-revision://openai/1",
      rotation_epoch: account.generation,
      fence_token: "#{account.account_ref}:fence:#{account.fence}",
      authority_ref: "citadel://grant/openai/1",
      authority_decision_ref: "citadel://decision/openai/1",
      authority_scope: ["model:invoke"],
      installation_revision: "installation://nshkr/1",
      effect_ref: "effect://openai/run-managed-cloud-1/turn-1",
      operation_ref: "operation://openai/chat-completions/1",
      endpoint_ref: account.endpoint_ref,
      max_calls: 1,
      max_tokens: 4096,
      allowed_models: ["gpt-4o-mini"],
      network_policy: :provider_only
    }
  end

  defp managed_redemption_context(context, now) do
    %{
      tenant_id: context.tenant_id,
      provider_family: context.provider_family,
      connector_instance_ref: context.connector_instance_ref,
      provider_account_ref: context.provider_account_ref,
      credential_handle_ref: context.credential_handle_ref,
      operation_class: context.operation_class,
      target_ref: context.target_ref,
      attach_grant_ref: context.attach_grant_ref,
      operation_policy_ref: context.operation_policy_ref,
      current_policy_revision_ref: context.policy_revision_ref,
      current_rotation_epoch: context.rotation_epoch,
      current_target_grant_revision: context.target_grant_revision,
      fence_token: context.fence_token,
      current_installation_revision: context.installation_revision,
      requested_authority_scope: context.authority_scope,
      requested_model: "gpt-4o-mini",
      requested_tokens: 512,
      network_target: :provider,
      now: DateTime.add(now, 2, :second)
    }
  end

  defp configure_asm_endpoint(text) do
    ASMRuntimeConfig.configure!(
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

  defp restore_runtime_config(config) do
    Enum.each(config, fn {key, value} ->
      :ok = RuntimeConfig.put(key, value)
    end)
  end

  defp sha256_ref?("sha256:" <> digest) when byte_size(digest) == 64 do
    digest
    |> String.downcase()
    |> :binary.bin_to_list()
    |> Enum.all?(fn
      char when char in ?0..?9 -> true
      char when char in ?a..?f -> true
      _other -> false
    end)
  end

  defp sha256_ref?(_value), do: false

  defp snapshot_control_plane_store_env do
    Map.new(@control_plane_store_keys, fn key ->
      {key, Application.fetch_env(:jido_integration_v2_control_plane, key)}
    end)
  end

  defp reset_control_plane_store_env do
    Enum.each(@control_plane_store_keys, fn key ->
      Application.delete_env(:jido_integration_v2_control_plane, key)
    end)

    Jido.Integration.V2.ControlPlane.Persistence.reset!()
    Jido.Integration.V2.Auth.Persistence.reset!()

    Jido.Integration.V2.ControlPlane.Persistence.configure!(
      profile: :mickey_mouse,
      store_modules: Jido.Integration.V2.ControlPlane.Persistence.test_store_modules()
    )

    Jido.Integration.V2.Auth.Persistence.configure!(
      profile: :mickey_mouse,
      store_modules: Jido.Integration.V2.Auth.Persistence.test_store_modules()
    )
  end

  defp restore_control_plane_store_env(previous_env) do
    Enum.each(previous_env, fn
      {key, {:ok, value}} -> Application.put_env(:jido_integration_v2_control_plane, key, value)
      {key, :error} -> Application.delete_env(:jido_integration_v2_control_plane, key)
    end)

    Jido.Integration.V2.ControlPlane.Persistence.reset!()
    Jido.Integration.V2.Auth.Persistence.reset!()
  end
end
