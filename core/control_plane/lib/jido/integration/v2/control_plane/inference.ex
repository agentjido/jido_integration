defmodule Jido.Integration.V2.ControlPlane.Inference do
  @moduledoc false

  alias Jido.Integration.V2.BackendManifest
  alias Jido.Integration.V2.CompatibilityResult
  alias Jido.Integration.V2.ConsumerManifest
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.ControlPlane.Inference.ReqLLMCallSpec
  alias Jido.Integration.V2.EndpointDescriptor
  alias Jido.Integration.V2.InferenceExecutionContext
  alias Jido.Integration.V2.InferenceRequest
  alias Jido.Integration.V2.InferenceResult
  alias Jido.Integration.V2.LeaseRef
  alias ReqLLM.Response
  alias ReqLLM.Response.Stream, as: ResponseStream

  @req_llm_passthrough_keys [
    :api_key,
    :frequency_penalty,
    :max_tokens,
    :presence_penalty,
    :provider_options,
    :req_http_options,
    :system_prompt,
    :telemetry,
    :temperature,
    :tool_choice,
    :tools,
    :top_p
  ]
  @default_accepted_runtime_kinds [:client, :task, :service]

  @type route_result :: %{
          target_class: Contracts.inference_target_class(),
          call_spec: ReqLLMCallSpec.t(),
          compatibility_result: CompatibilityResult.t(),
          endpoint_descriptor: EndpointDescriptor.t() | nil,
          backend_manifest: BackendManifest.t() | nil,
          lease_ref: LeaseRef.t() | nil
        }

  @type invoke_result :: %{
          request: InferenceRequest.t(),
          context: InferenceExecutionContext.t(),
          consumer_manifest: ConsumerManifest.t(),
          compatibility_result: CompatibilityResult.t(),
          endpoint_descriptor: EndpointDescriptor.t() | nil,
          backend_manifest: BackendManifest.t() | nil,
          lease_ref: LeaseRef.t() | nil,
          inference_result: InferenceResult.t(),
          stream: map() | nil,
          response_text: String.t() | nil,
          response_summary: map() | nil,
          run: Jido.Integration.V2.Run.t(),
          attempt: Jido.Integration.V2.Attempt.t()
        }

  @spec invoke(InferenceRequest.t() | map() | keyword(), keyword()) ::
          {:ok, invoke_result()} | {:error, term()}
  def invoke(request_or_attrs, opts \\ []) do
    with {:ok, request} <- normalize_request(request_or_attrs),
         execution_request = prepare_execution_request(request, opts),
         durable_request = sanitize_request_for_recording(execution_request),
         {:ok, context} <- build_context(durable_request, opts),
         {:ok, consumer_manifest} <- build_consumer_manifest(durable_request, opts),
         {:ok, route} <- resolve_route(execution_request, context, consumer_manifest, opts),
         {:ok, execution} <- execute_route(execution_request, context, route, opts),
         {:ok, recorded} <-
           ControlPlane.record_inference_attempt(%{
             request: durable_request,
             context: context,
             consumer_manifest: consumer_manifest,
             compatibility_result: route.compatibility_result,
             endpoint_descriptor: route.endpoint_descriptor,
             backend_manifest: route.backend_manifest,
             lease_ref: route.lease_ref,
             stream: execution.stream,
             result: execution.inference_result
           }) do
      {:ok,
       %{
         request: durable_request,
         context: context,
         consumer_manifest: consumer_manifest,
         compatibility_result: route.compatibility_result,
         endpoint_descriptor: route.endpoint_descriptor,
         backend_manifest: route.backend_manifest,
         lease_ref: route.lease_ref,
         inference_result: execution.inference_result,
         stream: execution.stream,
         response_text: execution.response_text,
         response_summary: execution.response_summary,
         run: recorded.run,
         attempt: recorded.attempt
       }}
    end
  end

  defp normalize_request(%InferenceRequest{} = request), do: {:ok, request}

  defp normalize_request(attrs) when is_map(attrs) or is_list(attrs),
    do: InferenceRequest.new(attrs)

  defp normalize_request(other), do: {:error, {:invalid_inference_request, other}}

  defp prepare_execution_request(%InferenceRequest{} = request, opts) do
    request
    |> normalize_model_provider()
    |> normalize_target_backend()
    |> merge_target_backend_options(Keyword.get(opts, :target_backend_options, %{}))
  end

  defp sanitize_request_for_recording(%InferenceRequest{} = request) do
    target_preference = map_or_empty(request.target_preference)

    durable_target_preference =
      case Contracts.get(target_preference, :backend_options) do
        nil ->
          target_preference

        backend_options ->
          put_normalized_field(
            target_preference,
            :backend_options,
            sanitize_json_safe(backend_options)
          )
      end

    %InferenceRequest{request | target_preference: durable_target_preference}
  end

  defp normalize_model_provider(%InferenceRequest{} = request) do
    model_preference = map_or_empty(request.model_preference)

    case Contracts.get(model_preference, :provider) do
      nil ->
        request

      provider ->
        %InferenceRequest{
          request
          | model_preference:
              put_normalized_field(
                model_preference,
                :provider,
                Contracts.normalize_atomish!(provider, "model_preference.provider")
              )
        }
    end
  end

  defp normalize_target_backend(%InferenceRequest{} = request) do
    target_preference = map_or_empty(request.target_preference)

    case Contracts.get(target_preference, :backend) do
      nil ->
        request

      backend ->
        %InferenceRequest{
          request
          | target_preference:
              put_normalized_field(
                target_preference,
                :backend,
                Contracts.normalize_atomish!(backend, "target_preference.backend")
              )
        }
    end
  end

  defp build_context(%InferenceRequest{} = request, opts) do
    run_id = Keyword.get_lazy(opts, :run_id, fn -> Contracts.next_id("run-inference") end)
    attempt_id = Contracts.attempt_id(run_id, 1)

    trace =
      opts
      |> Keyword.get(:observability, %{})
      |> Map.new()
      |> Map.merge(
        %{}
        |> maybe_put(:trace_id, Keyword.get(opts, :trace_id))
        |> maybe_put(:span_id, Keyword.get(opts, :span_id))
        |> maybe_put(:correlation_id, Keyword.get(opts, :correlation_id))
        |> maybe_put(:causation_id, Keyword.get(opts, :causation_id))
      )

    metadata =
      opts
      |> Keyword.get(:context_metadata, %{})
      |> Map.new()
      |> Map.put_new(:phase, "phase_1")
      |> maybe_put(:tenant_id, Contracts.get(request.metadata, :tenant_id))

    InferenceExecutionContext.new(
      run_id: run_id,
      attempt_id: attempt_id,
      authority_source: Keyword.get(opts, :authority_source, :jido_integration),
      decision_ref: Keyword.get(opts, :decision_ref),
      authority_ref: Keyword.get(opts, :authority_ref),
      boundary_ref: Keyword.get(opts, :boundary_ref),
      credential_scope: Map.new(Keyword.get(opts, :credential_scope, %{})),
      network_policy: network_policy(opts),
      observability: trace,
      streaming_policy: %{checkpoint_policy: checkpoint_policy(request, opts)},
      replay: replay_policy(request, opts),
      metadata: metadata
    )
  end

  defp build_consumer_manifest(%InferenceRequest{} = request, opts) do
    target_preference = map_or_empty(request.target_preference)

    ConsumerManifest.new(
      consumer: :jido_integration_req_llm,
      accepted_runtime_kinds:
        Keyword.get(opts, :accepted_runtime_kinds, @default_accepted_runtime_kinds),
      accepted_management_modes:
        Keyword.get(
          opts,
          :accepted_management_modes,
          [:provider_managed, :jido_managed, :externally_managed]
        ),
      accepted_protocols: Keyword.get(opts, :accepted_protocols, [:openai_chat_completions]),
      required_capabilities: required_capabilities(request),
      optional_capabilities: optional_capabilities(request),
      constraints:
        %{}
        |> maybe_put(:startup_kind, Contracts.get(target_preference, :startup_kind))
        |> Map.merge(Map.new(Keyword.get(opts, :consumer_constraints, %{}))),
      metadata:
        %{
          adapter: :req_llm,
          runtime_family: :inference
        }
        |> Map.merge(Map.new(Keyword.get(opts, :consumer_metadata, %{})))
    )
  end

  defp resolve_route(
         %InferenceRequest{} = request,
         %InferenceExecutionContext{} = context,
         consumer_manifest,
         opts
       ) do
    case target_class(request) do
      :cloud_provider ->
        resolve_cloud_route(request, context)

      :self_hosted_endpoint ->
        resolve_self_hosted_route(request, context, consumer_manifest, opts)

      :cli_endpoint ->
        resolve_cli_route(request, context, consumer_manifest)
    end
  end

  defp resolve_cloud_route(%InferenceRequest{} = request, %InferenceExecutionContext{} = context) do
    model_preference = map_or_empty(request.model_preference)

    with provider when not is_nil(provider) <- Contracts.get(model_preference, :provider),
         model_id when not is_nil(model_id) <-
           Contracts.get(model_preference, :id, Contracts.get(model_preference, :model)) do
      route = %{
        provider: provider,
        id: model_id,
        base_url: Contracts.get(model_preference, :base_url),
        options: %{}
      }

      {:ok,
       %{
         target_class: :cloud_provider,
         call_spec: ReqLLMCallSpec.from_cloud_route(request, context, route),
         compatibility_result:
           CompatibilityResult.new!(%{
             compatible?: true,
             reason: :protocol_match,
             resolved_runtime_kind: :client,
             resolved_management_mode: :provider_managed,
             resolved_protocol: nil,
             warnings: [],
             missing_requirements: [],
             metadata: %{
               route: :cloud,
               provider: Contracts.normalize_atomish!(provider, "cloud.provider"),
               model: Contracts.validate_non_empty_string!(to_string(model_id), "cloud.id")
             }
           }),
         endpoint_descriptor: nil,
         backend_manifest: nil,
         lease_ref: nil
       }}
    else
      nil ->
        {:error, {:invalid_cloud_model_preference, model_preference}}
    end
  end

  defp resolve_self_hosted_route(
         %InferenceRequest{} = request,
         %InferenceExecutionContext{} = context,
         %ConsumerManifest{} = consumer_manifest,
         opts
       ) do
    request =
      merge_target_backend_options(request, Keyword.get(opts, :target_backend_options, %{}))

    with {:ok, provider} <- fetch_self_hosted_endpoint_provider(opts),
         {:ok, resolution} <- provider.ensure_endpoint(request, consumer_manifest, context, opts),
         %{endpoint_descriptor: %EndpointDescriptor{} = endpoint_descriptor} <- resolution,
         %{compatibility_result: %CompatibilityResult{} = compatibility_result} <- resolution,
         %{backend_manifest: %BackendManifest{} = backend_manifest} <- resolution,
         lease_ref <- build_lease_ref(endpoint_descriptor, context, opts) do
      {:ok,
       %{
         target_class: :self_hosted_endpoint,
         call_spec: ReqLLMCallSpec.from_endpoint(request, context, endpoint_descriptor),
         compatibility_result: compatibility_result,
         endpoint_descriptor: endpoint_descriptor,
         backend_manifest: backend_manifest,
         lease_ref: lease_ref
       }}
    end
  end

  defp fetch_self_hosted_endpoint_provider(opts) do
    case Keyword.get(opts, :self_hosted_endpoint_provider) ||
           Application.get_env(
             :jido_integration_v2_control_plane,
             :self_hosted_endpoint_provider
           ) do
      nil ->
        {:error, :self_hosted_endpoint_provider_not_configured}

      provider when is_atom(provider) ->
        if Code.ensure_loaded?(provider) and function_exported?(provider, :ensure_endpoint, 4) do
          {:ok, provider}
        else
          {:error, {:invalid_self_hosted_endpoint_provider, provider}}
        end

      other ->
        {:error, {:invalid_self_hosted_endpoint_provider, other}}
    end
  end

  defp resolve_cli_route(
         %InferenceRequest{} = request,
         %InferenceExecutionContext{} = context,
         %ConsumerManifest{} = consumer_manifest
       ) do
    with {:ok, raw_endpoint, raw_compatibility} <-
           ASM.InferenceEndpoint.ensure_endpoint(request, consumer_manifest, context),
         endpoint_descriptor <- EndpointDescriptor.new!(Map.from_struct(raw_endpoint)),
         compatibility_result <-
           CompatibilityResult.new!(
             raw_compatibility
             |> Map.from_struct()
             |> Map.update!(:metadata, &Map.put(Map.new(&1), :route, :cli))
           ),
         {:ok, backend_manifest_data} <- cli_backend_manifest_data(endpoint_descriptor),
         backend_manifest <- BackendManifest.new!(backend_manifest_data),
         lease_ref <- build_lease_ref(endpoint_descriptor, context, []) do
      {:ok,
       %{
         target_class: :cli_endpoint,
         call_spec: ReqLLMCallSpec.from_endpoint(request, context, endpoint_descriptor),
         compatibility_result: compatibility_result,
         endpoint_descriptor: endpoint_descriptor,
         backend_manifest: backend_manifest,
         lease_ref: lease_ref
       }}
    end
  end

  defp execute_route(
         %InferenceRequest{} = request,
         %InferenceExecutionContext{} = context,
         route,
         opts
       ) do
    call_spec = route.call_spec
    input = call_input(call_spec)
    call_opts = req_llm_opts(call_spec, opts)

    case call_spec.operation do
      :generate_text ->
        execute_generate_text(input, context, route, call_spec.model_spec, call_opts)

      :stream_text ->
        execute_stream_text(input, context, route, call_spec.model_spec, call_opts, request)
    end
  end

  defp execute_generate_text(input, context, route, model_spec, call_opts) do
    with {:ok, response} <- ReqLLM.generate_text(model_spec, input, call_opts) do
      response_text = Response.text(response)

      {:ok,
       %{
         response_text: response_text,
         response_summary: response_summary(response, response_text),
         stream: nil,
         inference_result:
           InferenceResult.new!(%{
             run_id: context.run_id,
             attempt_id: context.attempt_id,
             status: :ok,
             streaming?: false,
             endpoint_id: route.endpoint_descriptor && route.endpoint_descriptor.endpoint_id,
             stream_id: nil,
             finish_reason: Response.finish_reason(response) || :stop,
             usage: Response.usage(response),
             error: nil,
             metadata:
               %{
                 route: route.target_class,
                 response_id: response.id,
                 model: response.model,
                 text: response_text
               }
               |> maybe_put(:provider, cloud_provider(route))
               |> Contracts.dump_json_safe!()
           })
       }}
    end
  end

  defp execute_stream_text(input, context, route, model_spec, call_opts, request) do
    with {:ok, stream_response} <- ReqLLM.stream_text(model_spec, input, call_opts) do
      chunks = Enum.to_list(stream_response.stream)
      summary = ResponseStream.summarize(chunks)
      stream_id = Contracts.next_id("stream")
      chunk_count = count_content_chunks(chunks)
      byte_count = byte_size(summary.text)
      protocol = stream_protocol(route)
      checkpoint_policy = checkpoint_policy(context)

      {:ok,
       %{
         response_text: summary.text,
         response_summary: Contracts.dump_json_safe!(summary),
         stream: %{
           opened: %{
             stream_id: stream_id,
             protocol: protocol,
             checkpoint_policy: checkpoint_policy
           },
           checkpoints:
             build_stream_checkpoints(stream_id, checkpoint_policy, chunk_count, byte_count),
           closed: %{
             stream_id: stream_id,
             finish_reason: summary.finish_reason || :stop,
             chunk_count: chunk_count,
             byte_count: byte_count
           }
         },
         inference_result:
           InferenceResult.new!(%{
             run_id: context.run_id,
             attempt_id: context.attempt_id,
             status: :ok,
             streaming?: true,
             endpoint_id: route.endpoint_descriptor && route.endpoint_descriptor.endpoint_id,
             stream_id: stream_id,
             finish_reason: summary.finish_reason || :stop,
             usage: summary.usage,
             error: nil,
             metadata:
               %{
                 route: route.target_class,
                 text: summary.text,
                 thinking: summary.thinking,
                 tool_calls: summary.tool_calls,
                 chunk_count: chunk_count,
                 byte_count: byte_count,
                 request_stream?: request.stream?
               }
               |> maybe_put(:provider, cloud_provider(route))
               |> Contracts.dump_json_safe!()
           })
       }}
    end
  end

  defp merge_target_backend_options(%InferenceRequest{} = request, extra_options)
       when is_map(extra_options) and map_size(extra_options) > 0 do
    target_preference = map_or_empty(request.target_preference)

    backend_options =
      target_preference
      |> Contracts.get(:backend_options, %{})
      |> Map.new()
      |> Map.merge(extra_options)

    %InferenceRequest{
      request
      | target_preference:
          put_normalized_field(target_preference, :backend_options, backend_options)
    }
  end

  defp merge_target_backend_options(%InferenceRequest{} = request, _extra_options), do: request

  defp put_normalized_field(map, key, value) when is_map(map) do
    map
    |> Map.delete(key)
    |> Map.delete(Atom.to_string(key))
    |> Map.put(key, value)
  end

  defp sanitize_json_safe(%DateTime{} = value), do: value
  defp sanitize_json_safe(%NaiveDateTime{} = value), do: value
  defp sanitize_json_safe(%Date{} = value), do: value
  defp sanitize_json_safe(%Time{} = value), do: value
  defp sanitize_json_safe(%_{} = value), do: value |> Map.from_struct() |> sanitize_json_safe()

  defp sanitize_json_safe(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      case sanitize_json_safe(nested_value) do
        :drop -> acc
        sanitized -> Map.put(acc, key, sanitized)
      end
    end)
  end

  defp sanitize_json_safe(value) when is_list(value) do
    value
    |> Enum.map(&sanitize_json_safe/1)
    |> Enum.reject(&(&1 == :drop))
  end

  defp sanitize_json_safe(value)
       when is_atom(value) or is_binary(value) or is_integer(value) or is_float(value) or
              is_boolean(value) or is_nil(value),
       do: value

  defp sanitize_json_safe(_value), do: :drop

  defp build_lease_ref(%EndpointDescriptor{lease_ref: nil}, _context, _opts), do: nil

  defp build_lease_ref(%EndpointDescriptor{} = endpoint_descriptor, context, opts) do
    route =
      case endpoint_descriptor.target_class do
        :cli_endpoint -> :cli
        _other -> :self_hosted
      end

    LeaseRef.new!(%{
      lease_ref: endpoint_descriptor.lease_ref,
      owner_ref: Keyword.get(opts, :owner_ref, context.attempt_id),
      ttl_ms: Keyword.get(opts, :ttl_ms, 60_000),
      renewable?: Keyword.get(opts, :renewable?, true),
      metadata:
        %{
          route: route,
          source_runtime_ref: endpoint_descriptor.source_runtime_ref
        }
        |> maybe_put(:boundary_ref, endpoint_descriptor.boundary_ref)
    })
  end

  defp cli_backend_manifest_data(%EndpointDescriptor{} = endpoint_descriptor) do
    metadata = map_or_empty(endpoint_descriptor.metadata)

    case Contracts.get(metadata, :backend_manifest) do
      %{} = manifest ->
        {:ok, manifest}

      nil ->
        {:error, {:missing_backend_manifest, endpoint_descriptor.endpoint_id}}

      other ->
        {:error, {:invalid_backend_manifest, other}}
    end
  end

  defp req_llm_opts(%ReqLLMCallSpec{} = call_spec, opts) do
    user_opts =
      opts
      |> Keyword.take(@req_llm_passthrough_keys)
      |> Map.new()

    req_http_options =
      user_opts
      |> Map.get(:req_http_options, [])
      |> normalize_req_http_options()
      |> merge_req_http_headers(call_spec.headers)

    call_spec.options
    |> Map.merge(Map.delete(user_opts, :req_http_options))
    |> maybe_put(:req_http_options, req_http_options)
    |> Map.to_list()
  end

  defp normalize_req_http_options(req_http_options) when is_list(req_http_options),
    do: req_http_options

  defp normalize_req_http_options(req_http_options) when is_map(req_http_options),
    do: Map.to_list(req_http_options)

  defp normalize_req_http_options(nil), do: []
  defp normalize_req_http_options(_other), do: []

  defp merge_req_http_headers(req_http_options, headers) when headers in [%{}, nil] do
    req_http_options
  end

  defp merge_req_http_headers(req_http_options, headers) do
    merged_headers =
      req_http_options
      |> Keyword.get(:headers, [])
      |> normalize_header_list()
      |> then(&Map.merge(Map.new(headers), &1))
      |> Enum.to_list()

    Keyword.put(req_http_options, :headers, merged_headers)
  end

  defp normalize_header_list(headers) when is_list(headers), do: Map.new(headers)
  defp normalize_header_list(headers) when is_map(headers), do: Map.new(headers)
  defp normalize_header_list(_headers), do: %{}

  defp call_input(%ReqLLMCallSpec{messages: [], prompt: prompt}) when is_binary(prompt),
    do: prompt

  defp call_input(%ReqLLMCallSpec{messages: messages}), do: messages

  defp target_class(%InferenceRequest{} = request) do
    target_preference = map_or_empty(request.target_preference)

    case Contracts.get(target_preference, :target_class) do
      nil ->
        if Contracts.get(target_preference, :backend) do
          :self_hosted_endpoint
        else
          :cloud_provider
        end

      value ->
        Contracts.validate_inference_target_class!(value)
    end
  end

  defp checkpoint_policy(%InferenceRequest{stream?: true}, opts),
    do: Keyword.get(opts, :checkpoint_policy, :summary)

  defp checkpoint_policy(%InferenceRequest{}, _opts), do: :disabled

  defp checkpoint_policy(%InferenceExecutionContext{} = context) do
    context.streaming_policy
    |> Contracts.get(:checkpoint_policy, :disabled)
    |> Contracts.validate_inference_checkpoint_policy!()
  end

  defp replay_policy(%InferenceRequest{stream?: true}, opts) do
    %{
      replayable?: Keyword.get(opts, :replayable?, true),
      recovery_class: Keyword.get(opts, :recovery_class, :checkpoint_resume)
    }
  end

  defp replay_policy(%InferenceRequest{}, opts) do
    %{
      replayable?: Keyword.get(opts, :replayable?, false),
      recovery_class: Keyword.get(opts, :recovery_class)
    }
  end

  defp network_policy(opts) do
    opts
    |> Keyword.get(:network_policy, %{})
    |> Map.new()
    |> maybe_put(:egress, Keyword.get(opts, :egress))
  end

  defp required_capabilities(%InferenceRequest{stream?: true}), do: %{streaming?: true}
  defp required_capabilities(%InferenceRequest{}), do: %{}

  defp optional_capabilities(%InferenceRequest{} = request) do
    case Contracts.get(request.tool_policy, :tools) do
      tools when is_list(tools) and tools != [] -> %{tool_calling?: true}
      _ -> %{}
    end
  end

  defp response_summary(%Response{} = response, response_text) do
    %{
      id: response.id,
      model: response.model,
      finish_reason: Response.finish_reason(response),
      usage: Response.usage(response),
      text: response_text
    }
    |> Contracts.dump_json_safe!()
  end

  defp count_content_chunks(chunks) do
    Enum.count(chunks, &match?(%ReqLLM.StreamChunk{type: :content}, &1))
  end

  defp build_stream_checkpoints(_stream_id, :disabled, _chunk_count, _byte_count), do: []

  defp build_stream_checkpoints(stream_id, _checkpoint_policy, chunk_count, byte_count) do
    [
      %{
        stream_id: stream_id,
        chunk_count: chunk_count,
        byte_count: byte_count,
        content_artifact_id: nil
      }
    ]
  end

  defp stream_protocol(%{endpoint_descriptor: %EndpointDescriptor{} = endpoint_descriptor}) do
    endpoint_descriptor.protocol
  end

  defp stream_protocol(_route), do: :openai_chat_completions

  defp cloud_provider(%{target_class: :cloud_provider, call_spec: %ReqLLMCallSpec{} = call_spec}) do
    Contracts.get(call_spec.model_spec, :provider)
  end

  defp cloud_provider(_route), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp map_or_empty(nil), do: %{}
  defp map_or_empty(%{} = value), do: Map.new(value)
end
