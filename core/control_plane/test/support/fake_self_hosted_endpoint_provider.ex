defmodule Jido.Integration.V2.ControlPlane.TestSupport.FakeSelfHostedEndpointProvider do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.Inference.SelfHostedEndpointProvider
  @registry __MODULE__.Registry

  alias Jido.Integration.V2.BackendManifest
  alias Jido.Integration.V2.CompatibilityResult
  alias Jido.Integration.V2.ConsumerManifest
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.EndpointDescriptor
  alias Jido.Integration.V2.InferenceExecutionContext
  alias Jido.Integration.V2.InferenceRequest

  @impl true
  def ensure_endpoint(
        %InferenceRequest{} = request,
        %ConsumerManifest{} = consumer_manifest,
        %InferenceExecutionContext{} = _context,
        _opts
      ) do
    with {:ok, backend} <- fetch_target_backend(request) do
      {:ok, endpoint_and_backend(request, consumer_manifest, backend)}
    end
  end

  def cleanup! do
    case Process.whereis(@registry) do
      nil ->
        :ok

      pid ->
        pid
        |> Agent.get_and_update(fn state -> {Map.values(state), %{}} end)
        |> Enum.each(&stop_llama_server/1)

        Agent.stop(pid, :normal)
    end

    :ok
  catch
    :exit, _reason -> :ok
  end

  defp endpoint_and_backend(
         %InferenceRequest{} = request,
         %ConsumerManifest{} = consumer_manifest,
         :llama_cpp_sdk
       ) do
    boot_spec =
      request.target_preference
      |> Map.new()
      |> Contracts.get(:boot_spec, %{})
      |> Map.new()

    host = Contracts.get(boot_spec, :host, "127.0.0.1")
    port = Contracts.get(boot_spec, :port)
    api_prefix = Contracts.get(boot_spec, :api_prefix, "/managed")
    api_key = Contracts.get(boot_spec, :api_key, "fixture-token")
    model_id = request.model_preference |> Map.new() |> Contracts.get(:id, "fixture-llama")

    :ok = ensure_llama_server_started(boot_spec)

    %{
      endpoint_descriptor:
        EndpointDescriptor.new!(%{
          endpoint_id: "endpoint-llama_cpp_sdk-1",
          runtime_kind: :service,
          management_mode: :jido_managed,
          target_class: :self_hosted_endpoint,
          protocol: :openai_chat_completions,
          base_url: "http://#{host}:#{port}#{api_prefix}/v1",
          headers: %{
            "authorization" => "Bearer #{api_key}",
            "x-jido-route" => "inference"
          },
          provider_identity: :llama_cpp_sdk,
          model_identity: model_id,
          source_runtime: :llama_cpp_sdk,
          source_runtime_ref: "llama-runtime-1",
          lease_ref: "lease-llama_cpp_sdk-1",
          health_ref: "health-llama_cpp_sdk-1",
          boundary_ref: nil,
          capabilities: %{streaming?: true, tool_calling?: false},
          metadata: %{consumer: consumer_manifest.consumer}
        }),
      compatibility_result:
        CompatibilityResult.new!(%{
          compatible?: true,
          reason: :protocol_match,
          resolved_runtime_kind: :service,
          resolved_management_mode: :jido_managed,
          resolved_protocol: :openai_chat_completions,
          warnings: [],
          missing_requirements: [],
          metadata: %{route: :self_hosted, backend: :llama_cpp_sdk}
        }),
      backend_manifest:
        BackendManifest.new!(%{
          backend: :llama_cpp_sdk,
          runtime_kind: :service,
          management_modes: [:jido_managed],
          startup_kind: :spawned,
          protocols: [:openai_chat_completions],
          capabilities: %{streaming?: true, tool_calling?: false, embeddings?: :unknown},
          supported_surfaces: [:local_subprocess],
          resource_profile: %{profile: "fixture"},
          metadata: %{family: "llama_cpp"}
        })
    }
  end

  defp endpoint_and_backend(
         %InferenceRequest{} = request,
         %ConsumerManifest{} = consumer_manifest,
         :ollama
       ) do
    backend_options =
      request.target_preference
      |> Map.new()
      |> Contracts.get(:backend_options, %{})
      |> Map.new()

    root_url = Contracts.get(backend_options, :root_url)
    model_id = request.model_preference |> Map.new() |> Contracts.get(:id, "llama3.2")

    %{
      endpoint_descriptor:
        EndpointDescriptor.new!(%{
          endpoint_id: "endpoint-ollama-1",
          runtime_kind: :service,
          management_mode: :externally_managed,
          target_class: :self_hosted_endpoint,
          protocol: :openai_chat_completions,
          base_url: root_url <> "/v1",
          headers: %{},
          provider_identity: :ollama,
          model_identity: model_id,
          source_runtime: :ollama,
          source_runtime_ref: "ollama-runtime-1",
          lease_ref: "lease-ollama-1",
          health_ref: "health-ollama-1",
          boundary_ref: nil,
          capabilities: %{streaming?: true, tool_calling?: false},
          metadata: %{consumer: consumer_manifest.consumer}
        }),
      compatibility_result:
        CompatibilityResult.new!(%{
          compatible?: true,
          reason: :protocol_match,
          resolved_runtime_kind: :service,
          resolved_management_mode: :externally_managed,
          resolved_protocol: :openai_chat_completions,
          warnings: [],
          missing_requirements: [],
          metadata: %{route: :self_hosted, backend: :ollama}
        }),
      backend_manifest:
        BackendManifest.new!(%{
          backend: :ollama,
          runtime_kind: :service,
          management_modes: [:externally_managed],
          startup_kind: :attach_existing_service,
          protocols: [:openai_chat_completions],
          capabilities: %{streaming?: true, tool_calling?: false, embeddings?: :unknown},
          supported_surfaces: [:local_subprocess],
          resource_profile: %{profile: "attached_local"},
          metadata: %{family: "ollama"}
        })
    }
  end

  defp fetch_target_backend(%InferenceRequest{} = request) do
    case request.target_preference |> Map.new() |> Contracts.get(:backend) do
      nil -> {:error, {:missing_target_preference, :backend}}
      backend -> {:ok, Contracts.normalize_atomish!(backend, "target_preference.backend")}
    end
  end

  defp ensure_llama_server_started(boot_spec) do
    host = Contracts.get(boot_spec, :host, "127.0.0.1")
    port = Contracts.get(boot_spec, :port)
    key = {host, port}
    registry = ensure_registry()

    case Agent.get(registry, &Map.get(&1, key)) do
      nil ->
        server = start_llama_server(boot_spec)
        wait_for_llama_health!(boot_spec)
        Agent.update(registry, &Map.put(&1, key, server))
        :ok

      _server ->
        :ok
    end
  end

  defp ensure_registry do
    case Process.whereis(@registry) do
      nil ->
        {:ok, pid} = Agent.start_link(fn -> %{} end, name: @registry)
        pid

      pid ->
        pid
    end
  end

  defp start_llama_server(boot_spec) do
    binary_path =
      Contracts.get(boot_spec, :binary_path, System.find_executable("python3") || "python3")

    [script_path | _rest] = List.wrap(Contracts.get(boot_spec, :launcher_args, []))

    args =
      [
        script_path,
        "--model",
        Contracts.get(boot_spec, :model),
        "--alias",
        Contracts.get(boot_spec, :alias, "fixture-llama"),
        "--host",
        Contracts.get(boot_spec, :host, "127.0.0.1"),
        "--port",
        to_string(Contracts.get(boot_spec, :port)),
        "--api-key",
        Contracts.get(boot_spec, :api_key, "fixture-token"),
        "--api-prefix",
        Contracts.get(boot_spec, :api_prefix, "/managed")
      ]
      |> Enum.map(&to_charlist/1)

    env =
      boot_spec
      |> Contracts.get(:environment, %{})
      |> Enum.map(fn {key, value} ->
        {key |> to_string() |> to_charlist(), value |> to_string() |> to_charlist()}
      end)

    port =
      Port.open({:spawn_executable, binary_path}, [
        :binary,
        :exit_status,
        :hide,
        :stderr_to_stdout,
        args: args,
        env: env
      ])

    %{port: port}
  end

  defp wait_for_llama_health!(boot_spec, attempts_left \\ 40)

  defp wait_for_llama_health!(_boot_spec, 0) do
    raise "fake llama server failed to become healthy"
  end

  defp wait_for_llama_health!(boot_spec, attempts_left) do
    host = Contracts.get(boot_spec, :host, "127.0.0.1")
    port = Contracts.get(boot_spec, :port)
    api_prefix = Contracts.get(boot_spec, :api_prefix, "/managed")
    url = ~c"http://#{host}:#{port}#{api_prefix}/health"

    case :httpc.request(:get, {url, []}, [], body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, _body}} ->
        :ok

      _other ->
        Process.sleep(50)
        wait_for_llama_health!(boot_spec, attempts_left - 1)
    end
  end

  defp stop_llama_server(%{port: port}) when is_port(port) do
    Port.close(port)
    :ok
  catch
    :exit, _reason -> :ok
  end
end
