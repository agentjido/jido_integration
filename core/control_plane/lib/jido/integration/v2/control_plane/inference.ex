defmodule Jido.Integration.V2.ControlPlane.Inference do
  @moduledoc false

  alias Jido.Integration.V2.BackendManifest
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.SecretGuard
  alias Jido.Integration.V2.CompatibilityResult
  alias Jido.Integration.V2.ConsumerManifest
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.ControlPlane.Inference.CallPlan
  alias Jido.Integration.V2.ControlPlane.InferenceRecorder
  alias Jido.Integration.V2.ControlPlane.RuntimeConfig
  alias Jido.Integration.V2.EndpointDescriptor
  alias Jido.Integration.V2.InferenceExecutionContext
  alias Jido.Integration.V2.InferenceRequest
  alias Jido.Integration.V2.InferenceResult
  alias Jido.Integration.V2.LeaseRef
  alias Jido.Integration.V2.MaterializationRequest
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.SecretMaterial
  alias Jido.Integration.ProviderMaterializer
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
  @default_token_budget_max_tokens 2_048
  @default_accepted_runtime_kinds [:client, :task, :service]

  @type route_result :: %{
          target_class: Contracts.inference_target_class(),
          call_plan: CallPlan.t(),
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
          credential_lease_id: String.t() | nil,
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
         :ok <- reject_managed_secret_supplementation(execution_request, opts),
         {:ok, credential_mode} <- credential_mode(execution_request, opts),
         {:ok, durable_request} <- sanitize_request_for_recording(execution_request, opts),
         {:ok, context} <- build_context(durable_request, opts),
         {:ok, consumer_manifest} <- build_consumer_manifest(durable_request, opts),
         {:ok, route} <-
           resolve_route(execution_request, context, consumer_manifest, credential_mode, opts),
         :ok <- validate_route_credential_mode(route, credential_mode),
         :ok <- enforce_required_descriptor_refs(route, opts) do
      execute_and_record(
        execution_request,
        durable_request,
        context,
        consumer_manifest,
        route,
        credential_mode,
        opts
      )
    end
  end

  defp normalize_request(%InferenceRequest{} = request), do: {:ok, request}

  defp normalize_request(attrs) when is_map(attrs) or is_list(attrs),
    do: InferenceRequest.new(attrs)

  defp normalize_request(_other), do: {:error, :invalid_inference_request}

  defp prepare_execution_request(%InferenceRequest{} = request, opts) do
    request
    |> normalize_model_provider()
    |> normalize_target_backend()
    |> merge_target_backend_options(Keyword.get(opts, :target_backend_options, %{}))
  end

  defp sanitize_request_for_recording(%InferenceRequest{} = request, opts) do
    target_preference = map_or_empty(request.target_preference)

    durable_target_preference =
      case Contracts.get(target_preference, :backend_options) do
        nil ->
          target_preference

        backend_options ->
          with :ok <- SecretGuard.validate_durable(backend_options) do
            put_normalized_field(
              target_preference,
              :backend_options,
              sanitize_json_safe(backend_options)
            )
          end
      end

    with %{} = durable_target_preference <- durable_target_preference do
      request = %InferenceRequest{request | target_preference: durable_target_preference}

      if Keyword.get(opts, :require_artifact_refs?, false) do
        enforce_prompt_artifact_ref(request)
      else
        {:ok, request}
      end
    end
  end

  defp reject_managed_secret_supplementation(request, opts) do
    if managed_request?(request, opts) do
      with :ok <-
             opts
             |> Keyword.take([
               :api_key,
               :provider_options,
               :req_http_options,
               :target_backend_options
             ])
             |> Map.new()
             |> SecretGuard.validate_durable(),
           :ok <- request |> Map.from_struct() |> SecretGuard.validate_durable(),
           :ok <- reject_managed_direct_options(opts) do
        :ok
      end
    else
      :ok
    end
  end

  defp managed_request?(request, opts) do
    requested_management_mode(request) == :jido_managed or
      Enum.any?(
        [
          :managed_account_ref,
          :credential_lease,
          :materialization_request,
          :materialization_context
        ],
        &Keyword.has_key?(opts, &1)
      )
  end

  defp reject_managed_direct_options(opts) do
    case Enum.find([:api_key, :provider_options, :req_http_options], &Keyword.has_key?(opts, &1)) do
      nil -> :ok
      key -> {:error, {:managed_direct_credential_option_forbidden, key}}
    end
  end

  defp credential_mode(request, opts) do
    if managed_request?(request, opts) do
      with :ok <- validate_requested_management_mode(request),
           :ok <- reject_removed_managed_account_option(opts),
           {:ok, lease} <- typed_managed_option(opts, :credential_lease, CredentialLease),
           {:ok, materialization_request} <-
             typed_managed_option(opts, :materialization_request, MaterializationRequest),
           {:ok, materialization_context} <- materialization_context(opts) do
        {:ok,
         %{
           kind: :managed,
           lease: lease,
           request: materialization_request,
           context: materialization_context
         }}
      end
    else
      {:ok, :standalone}
    end
  end

  defp validate_requested_management_mode(request) do
    case requested_management_mode(request) do
      nil -> :ok
      :jido_managed -> :ok
      mode -> {:error, {:managed_credential_mode_mismatch, mode}}
    end
  end

  defp requested_management_mode(%InferenceRequest{} = request) do
    request.target_preference
    |> map_or_empty()
    |> Contracts.get(:management_mode)
    |> case do
      nil -> nil
      mode -> Contracts.normalize_atomish!(mode, "target_preference.management_mode")
    end
  end

  defp reject_removed_managed_account_option(opts) do
    if Keyword.has_key?(opts, :managed_account_ref),
      do: {:error, :managed_account_ref_option_removed},
      else: :ok
  end

  defp typed_managed_option(opts, key, module) do
    case Keyword.fetch(opts, key) do
      {:ok, %{__struct__: ^module} = value} -> {:ok, value}
      {:ok, _other} -> {:error, {:invalid_managed_credential_option, key}}
      :error -> {:error, {:managed_credential_materialization_required, key}}
    end
  end

  defp materialization_context(opts) do
    case Keyword.fetch(opts, :materialization_context) do
      {:ok, %{} = context} -> {:ok, context}
      {:ok, _other} -> {:error, {:invalid_managed_credential_option, :materialization_context}}
      :error -> {:error, {:managed_credential_materialization_required, :materialization_context}}
    end
  end

  defp enforce_prompt_artifact_ref(%InferenceRequest{} = request) do
    metadata = map_or_empty(request.metadata)
    artifact_ref = Contracts.get(metadata, :prompt_artifact_ref)

    cond do
      not raw_prompt_present?(request) ->
        {:ok, request}

      not (is_binary(artifact_ref) and artifact_ref != "") ->
        {:error, {:missing_required_artifact_ref, :prompt_or_messages}}

      true ->
        {:ok,
         %InferenceRequest{
           request
           | messages: [],
             prompt: nil,
             metadata: put_normalized_field(metadata, :prompt_artifact_ref, artifact_ref)
         }}
    end
  end

  defp raw_prompt_present?(%InferenceRequest{} = request) do
    request.prompt not in [nil, ""] or request.messages != []
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
         credential_mode,
         opts
       ) do
    case target_class(request) do
      :cloud_provider ->
        resolve_cloud_route(request, context, credential_mode)

      :self_hosted_endpoint ->
        resolve_self_hosted_route(request, context, consumer_manifest, opts)

      :cli_endpoint ->
        resolve_cli_route(request, context, consumer_manifest)
    end
  end

  defp enforce_required_descriptor_refs(route, opts) do
    if Keyword.get(opts, :require_descriptor_refs?, false) do
      route
      |> Map.get(:endpoint_descriptor)
      |> missing_descriptor_refs()
      |> case do
        [] -> :ok
        missing -> {:error, {:missing_required_inference_descriptor_refs, missing}}
      end
    else
      :ok
    end
  end

  defp missing_descriptor_refs(%EndpointDescriptor{} = endpoint_descriptor) do
    metadata = map_or_empty(endpoint_descriptor.metadata)

    []
    |> missing_ref("endpoint_id", endpoint_descriptor.endpoint_id)
    |> missing_ref("model_identity", endpoint_descriptor.model_identity)
    |> missing_ref("model_version", Contracts.get(metadata, :model_version))
  end

  defp missing_descriptor_refs(_endpoint_descriptor) do
    ["endpoint_id", "model_identity", "model_version"]
  end

  defp resolve_cloud_route(
         %InferenceRequest{} = request,
         %InferenceExecutionContext{} = context,
         credential_mode
       ) do
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
         call_plan: CallPlan.from_cloud_route(request, context, route),
         compatibility_result:
           CompatibilityResult.new!(%{
             compatible?: true,
             reason: :protocol_match,
             resolved_runtime_kind: :client,
             resolved_management_mode: resolved_management_mode(credential_mode),
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
         call_plan: CallPlan.from_endpoint(request, context, endpoint_descriptor),
         compatibility_result: compatibility_result,
         endpoint_descriptor: endpoint_descriptor,
         backend_manifest: backend_manifest,
         lease_ref: lease_ref
       }}
    end
  end

  defp fetch_self_hosted_endpoint_provider(opts) do
    case Keyword.get(opts, :self_hosted_endpoint_provider) ||
           RuntimeConfig.current().self_hosted_endpoint_provider do
      nil ->
        {:error, :self_hosted_endpoint_provider_not_configured}

      provider when is_atom(provider) ->
        if Code.ensure_loaded?(provider) and function_exported?(provider, :ensure_endpoint, 4) do
          {:ok, provider}
        else
          {:error, {:invalid_self_hosted_endpoint_provider, provider}}
        end

      other ->
        {:error, {:invalid_self_hosted_endpoint_provider, safe_kind(other)}}
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
         call_plan: CallPlan.from_endpoint(request, context, endpoint_descriptor),
         compatibility_result: compatibility_result,
         endpoint_descriptor: endpoint_descriptor,
         backend_manifest: backend_manifest,
         lease_ref: lease_ref
       }}
    end
  end

  defp execute_and_record(
         execution_request,
         durable_request,
         context,
         consumer_manifest,
         route,
         :standalone,
         opts
       ) do
    with {:ok, execution} <- execute_route(execution_request, context, route, :standalone, opts),
         record_spec =
           record_spec(durable_request, context, consumer_manifest, route, :standalone),
         {:ok, recorded} <-
           ControlPlane.record_inference_attempt(
             Map.merge(record_spec, %{
               stream: execution.stream,
               result: execution.inference_result
             })
           ) do
      {:ok,
       invocation_result(
         durable_request,
         context,
         consumer_manifest,
         route,
         :standalone,
         execution,
         recorded
       )}
    end
  end

  defp execute_and_record(
         execution_request,
         durable_request,
         context,
         consumer_manifest,
         route,
         %{kind: :managed} = credential_mode,
         opts
       ) do
    record_spec = record_spec(durable_request, context, consumer_manifest, route, credential_mode)

    with :ok <- validate_managed_call_plan(route.call_plan),
         :ok <- validate_managed_effect_alignment(route.call_plan, credential_mode.context),
         :ok <- verify_model_grant(route.call_plan, context, credential_mode, opts),
         {:ok, _started} <- InferenceRecorder.start_managed(record_spec) do
      case execute_route(execution_request, context, route, credential_mode, opts) do
        {:ok, execution} ->
          with {:ok, recorded} <-
                 InferenceRecorder.complete_managed(
                   Map.merge(record_spec, %{
                     stream: execution.stream,
                     result: execution.inference_result
                   })
                 ) do
            {:ok,
             invocation_result(
               durable_request,
               context,
               consumer_manifest,
               route,
               credential_mode,
               execution,
               recorded
             )}
          end

        {:error, reason} = error ->
          _ = InferenceRecorder.fail_managed(record_spec, reason)
          error
      end
    end
  end

  defp record_spec(request, context, consumer_manifest, route, credential_mode) do
    %{
      request: request,
      context: context,
      consumer_manifest: consumer_manifest,
      compatibility_result: route.compatibility_result,
      endpoint_descriptor: route.endpoint_descriptor,
      backend_manifest: route.backend_manifest,
      lease_ref: route.lease_ref,
      credential_lease_id: credential_lease_id(credential_mode)
    }
  end

  defp invocation_result(
         request,
         context,
         consumer_manifest,
         route,
         credential_mode,
         execution,
         recorded
       ) do
    %{
      request: request,
      context: context,
      consumer_manifest: consumer_manifest,
      compatibility_result: route.compatibility_result,
      endpoint_descriptor: route.endpoint_descriptor,
      backend_manifest: route.backend_manifest,
      lease_ref: route.lease_ref,
      credential_lease_id: credential_lease_id(credential_mode),
      inference_result: execution.inference_result,
      stream: execution.stream,
      response_text: execution.response_text,
      response_summary: execution.response_summary,
      run: recorded.run,
      attempt: recorded.attempt
    }
  end

  defp execute_route(
         %InferenceRequest{} = request,
         %InferenceExecutionContext{} = context,
         route,
         :standalone,
         opts
       ) do
    execute_call_plan(request, context, route, route.call_plan, opts)
  end

  defp execute_route(
         %InferenceRequest{} = request,
         %InferenceExecutionContext{} = context,
         route,
         %{kind: :managed} = credential_mode,
         opts
       ) do
    credential_mode.lease
    |> Auth.with_materialized_credential(
      credential_mode.request,
      credential_mode.context,
      fn material ->
        case execute_with_material(request, context, route, credential_mode, material, opts) do
          {:ok, execution} -> %{status: :ok, execution: execution}
          {:error, reason} -> %{status: :error, error_class: safe_error_class(reason)}
        end
      end
    )
    |> normalize_managed_execution()
  end

  defp execute_with_material(
         request,
         context,
         route,
         credential_mode,
         %SecretMaterial{} = material,
         opts
       ) do
    binding = provider_materialization_binding(route.call_plan, credential_mode, opts)

    with :ok <- validate_materialized_provider(route.call_plan, material),
         {:ok, authority} <- ProviderMaterializer.materialize(material, binding),
         {:ok, authority_refs} <- ProviderMaterializer.authority_refs(authority),
         {:ok, client} <-
           managed_inference_client(
             route.call_plan,
             credential_mode,
             authority_refs,
             authority
           ) do
      execute_managed_call_plan(request, context, route, route.call_plan, client, opts)
    end
  end

  defp execute_managed_call_plan(request, context, route, %CallPlan{} = call_plan, client, opts) do
    input = call_input(call_plan)
    request_opts = managed_request_opts(call_plan)
    durable_opts = Keyword.put(opts, :require_artifact_refs?, true)

    case call_plan.operation do
      :generate_text ->
        execute_managed_generate_text(input, context, route, client, request_opts, durable_opts)

      :stream_text ->
        execute_managed_stream_text(
          input,
          context,
          route,
          client,
          request_opts,
          request,
          durable_opts
        )
    end
  end

  defp execute_managed_generate_text(input, context, route, client, request_opts, opts) do
    with {:ok, response} <- Elixir.Inference.complete(client, input, request_opts),
         {:ok, finish_reason} <- normalize_managed_finish_reason(response.finish_reason) do
      response_text = Elixir.Inference.Response.text(response)
      usage = durable_managed_usage(response.usage)

      {:ok,
       %{
         response_text: response_text,
         response_summary:
           managed_response_summary(response, response_text, finish_reason, usage),
         stream: nil,
         inference_result:
           InferenceResult.new!(%{
             run_id: context.run_id,
             attempt_id: context.attempt_id,
             status: :ok,
             streaming?: false,
             endpoint_id: route.endpoint_descriptor && route.endpoint_descriptor.endpoint_id,
             stream_id: nil,
             finish_reason: finish_reason,
             usage: usage,
             error: nil,
             metadata:
               %{
                 route: route.target_class,
                 response_id: response.id,
                 model: response.model,
                 provider: :gemini
               }
               |> put_response_text_ref(response_text, opts)
               |> Contracts.dump_json_safe!()
           })
       }}
    end
  end

  defp execute_managed_stream_text(input, context, route, client, request_opts, request, opts) do
    with {:ok, enumerable} <- Elixir.Inference.stream(client, input, request_opts),
         {:ok, summary} <- consume_managed_stream(enumerable) do
      stream_id = Contracts.next_id("stream")
      checkpoint_policy = checkpoint_policy(context)
      usage = durable_managed_usage(summary.usage)

      {:ok,
       %{
         response_text: summary.text,
         response_summary:
           summary
           |> Map.drop([:checkpoints])
           |> Map.put(:usage, usage),
         stream: %{
           opened: %{
             stream_id: stream_id,
             protocol: stream_protocol(route),
             checkpoint_policy: checkpoint_policy
           },
           checkpoints:
             managed_stream_checkpoints(stream_id, checkpoint_policy, summary.checkpoints),
           closed: %{
             stream_id: stream_id,
             finish_reason: summary.finish_reason,
             chunk_count: summary.chunk_count,
             byte_count: summary.byte_count
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
             finish_reason: summary.finish_reason,
             usage: usage,
             error: nil,
             metadata:
               %{
                 route: route.target_class,
                 chunk_count: summary.chunk_count,
                 byte_count: summary.byte_count,
                 request_stream?: request.stream?,
                 provider: :gemini
               }
               |> put_response_text_ref(summary.text, opts)
               |> Contracts.dump_json_safe!()
           })
       }}
    end
  end

  defp execute_call_plan(request, context, route, %CallPlan{} = call_plan, opts) do
    input = call_input(call_plan)
    call_opts = req_llm_opts(call_plan, opts)

    case call_plan.operation do
      :generate_text ->
        execute_generate_text(input, context, route, call_plan.model_spec, call_opts, opts)

      :stream_text ->
        execute_stream_text(input, context, route, call_plan.model_spec, call_opts, request, opts)
    end
  end

  defp execute_generate_text(input, context, route, model_spec, call_opts, opts) do
    token_budget_call_opts = call_opts

    with {:ok, response} <- ReqLLM.generate_text(model_spec, input, token_budget_call_opts) do
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
                 model: response.model
               }
               |> put_response_text_ref(response_text, opts)
               |> maybe_put(:provider, cloud_provider(route))
               |> Contracts.dump_json_safe!()
           })
       }}
    end
  end

  defp execute_stream_text(input, context, route, model_spec, call_opts, request, opts) do
    token_budget_call_opts = call_opts

    with {:ok, stream_response} <- ReqLLM.stream_text(model_spec, input, token_budget_call_opts) do
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
                 thinking: summary.thinking,
                 tool_calls: summary.tool_calls,
                 chunk_count: chunk_count,
                 byte_count: byte_count,
                 request_stream?: request.stream?
               }
               |> put_response_text_ref(summary.text, opts)
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
        {:error, {:invalid_backend_manifest, safe_kind(other)}}
    end
  end

  defp req_llm_opts(%CallPlan{} = call_plan, opts) do
    user_opts =
      opts
      |> Keyword.take(@req_llm_passthrough_keys)
      |> Map.new()

    req_http_options =
      user_opts
      |> Map.get(:req_http_options, [])
      |> normalize_req_http_options()
      |> merge_req_http_headers(call_plan.headers)

    call_plan.options
    |> maybe_put(:api_key, call_plan.standalone_api_key)
    |> Map.merge(Map.delete(user_opts, :req_http_options))
    |> put_default_token_budget()
    |> maybe_put(:req_http_options, req_http_options)
    |> Map.to_list()
  end

  defp put_default_token_budget(%{} = opts) do
    case Map.get(opts, :max_tokens) do
      max_tokens when is_integer(max_tokens) and max_tokens > 0 ->
        opts

      _missing_or_invalid ->
        Map.put(opts, :max_tokens, @default_token_budget_max_tokens)
    end
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

  defp call_input(%CallPlan{messages: [], prompt: prompt}) when is_binary(prompt),
    do: prompt

  defp call_input(%CallPlan{messages: messages}), do: messages

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

  defp put_response_text_ref(metadata, response_text, opts) do
    if Keyword.get(opts, :require_artifact_refs?, false) do
      Map.put(metadata, :text_artifact_ref, response_artifact_ref(response_text))
    else
      Map.put(metadata, :text, response_text)
    end
  end

  defp response_artifact_ref(response_text) when is_binary(response_text) do
    content_hash = sha256_ref(response_text)
    "sha256:" <> digest = content_hash

    %{
      artifact_id: "jido.integration.inference.response:#{binary_part(digest, 0, 16)}",
      artifact_type: :inference_response_text,
      content_hash: content_hash,
      content_hash_alg: :sha256,
      byte_size: byte_size(response_text),
      media_type: "text/plain; charset=utf-8",
      retrieval_owner: :jido_integration_control_plane,
      release_manifest_ref: "phase5-v7-m8-ai-native-runtime-guardrails",
      safe_action: :quarantine_on_digest_mismatch
    }
  end

  defp sha256_ref(value) when is_binary(value) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, value), case: :lower)
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

  defp cloud_provider(%{target_class: :cloud_provider, call_plan: %CallPlan{} = call_plan}) do
    Contracts.get(call_plan.model_spec, :provider)
  end

  defp cloud_provider(_route), do: nil

  defp resolved_management_mode(:standalone), do: :provider_managed
  defp resolved_management_mode(%{kind: :managed}), do: :jido_managed

  defp validate_route_credential_mode(route, :standalone) do
    if :jido_managed in route_management_modes(route),
      do: {:error, {:route_credential_mode_mismatch, :standalone, :jido_managed}},
      else: :ok
  end

  defp validate_route_credential_mode(route, %{kind: :managed}) do
    resolved_mode = route.compatibility_result.resolved_management_mode
    descriptor_mode = route.endpoint_descriptor && route.endpoint_descriptor.management_mode

    cond do
      resolved_mode != :jido_managed ->
        {:error, {:route_credential_mode_mismatch, :managed, resolved_mode}}

      not is_nil(descriptor_mode) and descriptor_mode != :jido_managed ->
        {:error, {:route_credential_mode_mismatch, :managed, descriptor_mode}}

      true ->
        :ok
    end
  end

  defp route_management_modes(route) do
    [
      route.compatibility_result.resolved_management_mode,
      route.endpoint_descriptor && route.endpoint_descriptor.management_mode
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp credential_lease_id(:standalone), do: nil

  defp credential_lease_id(%{kind: :managed, lease: %CredentialLease{} = lease}),
    do: lease.lease_id

  defp validate_managed_call_plan(%CallPlan{} = call_plan) do
    cond do
      is_binary(call_plan.standalone_api_key) ->
        {:error, :managed_endpoint_credential_forbidden}

      true ->
        SecretGuard.validate_durable(call_plan.headers)
    end
  end

  defp validate_managed_effect_alignment(%CallPlan{} = call_plan, context) do
    expected_model = Contracts.get(call_plan.model_spec, :id)
    expected_provider = Contracts.get(call_plan.model_spec, :provider) |> to_string()

    cond do
      expected_provider != "gemini" ->
        {:error, {:managed_provider_not_supported, expected_provider}}

      context_value(context, :requested_model) != expected_model ->
        {:error, :managed_materialization_model_mismatch}

      to_string(context_value(context, :provider_family)) != expected_provider ->
        {:error, :managed_materialization_provider_mismatch}

      true ->
        :ok
    end
  end

  defp validate_materialized_provider(%CallPlan{} = call_plan, %SecretMaterial{} = material) do
    expected_provider = Contracts.get(call_plan.model_spec, :provider) |> to_string()

    if material.provider_family == expected_provider,
      do: :ok,
      else: {:error, :materialized_provider_mismatch}
  end

  defp verify_model_grant(call_plan, context, credential_mode, opts) do
    with {:ok, grant_ref} <- required_string_option(opts, :model_grant_ref),
         {:ok, binding} <- model_grant_binding(call_plan, context, credential_mode),
         %DateTime{} = now <- Keyword.get(opts, :now, DateTime.utc_now()),
         result <- Citadel.Governance.ModelAuthority.verify_grant(grant_ref, binding, now) do
      normalize_grant_verification(result)
    end
  end

  defp normalize_grant_verification(:ok), do: :ok
  defp normalize_grant_verification({:ok, _verified}), do: :ok
  defp normalize_grant_verification({:error, _reason} = error), do: error
  defp normalize_grant_verification(_other), do: {:error, :invalid_model_grant_verification}

  defp model_grant_binding(call_plan, context, credential_mode) do
    materialization_context = credential_mode.context
    request = credential_mode.request

    binding = %{
      decision_ref: context.decision_ref,
      input_digest: context_value(materialization_context, :model_grant_input_digest),
      policy_ref: context_value(materialization_context, :model_grant_policy_ref),
      policy_version: context_value(materialization_context, :model_grant_policy_version),
      tenant_ref: request.account.tenant_id,
      actor_ref: context_value(materialization_context, :actor_ref),
      subject_ref: context_value(materialization_context, :subject_ref),
      provider_family: request.account.provider_family,
      account_ref: request.account.account_ref,
      model_ref: Contracts.get(call_plan.model_spec, :id),
      operation_ref: request.operation_ref,
      operation_class: context_value(materialization_context, :model_grant_operation_class),
      context_ref: context_value(materialization_context, :execution_context_ref),
      context_digest: context_value(materialization_context, :context_digest),
      attempt_ref: context.attempt_id,
      effect_ref: request.effect_ref,
      fence_token: context_value(materialization_context, :fence_token)
    }

    missing =
      binding
      |> Enum.reject(fn
        {:policy_version, value} -> is_integer(value) and value > 0
        {_key, value} -> present_string?(value)
      end)
      |> Enum.map(&elem(&1, 0))

    if missing == [],
      do: {:ok, binding},
      else: {:error, {:model_grant_binding_missing, Enum.sort(missing)}}
  end

  defp provider_materialization_binding(call_plan, credential_mode, _opts) do
    context = credential_mode.context
    request = credential_mode.request

    %{
      base_url: call_plan.base_url,
      provider_ref: context_value(context, :provider_ref),
      model_account_ref: request.account.account_ref,
      credential_handle_ref: context_value(context, :credential_handle_ref),
      operation_policy_ref: context_value(context, :operation_policy_ref),
      redaction_ref: context_value(context, :redaction_ref),
      materialization_request: request,
      endpoint_ref: request.endpoint_ref,
      authority_ref: request.authority_ref,
      operation_ref: request.operation_ref,
      target_ref: request.target_ref,
      fence: request.account.fence
    }
  end

  defp managed_inference_client(call_plan, credential_mode, provider_refs, authority) do
    adapter = Inference.Adapters.GeminiExManaged

    with :ok <- validate_managed_adapter(adapter),
         {:ok, authority_projection} <-
           managed_authority_projection(call_plan, credential_mode, provider_refs),
         {:ok, client} <-
           Elixir.Inference.Client.new(%{
             adapter: adapter,
             provider: :gemini,
             model: Contracts.get(call_plan.model_spec, :id),
             authority: authority_projection,
             adapter_opts: [governed_authority: authority]
           }) do
      {:ok, client}
    end
  end

  defp validate_managed_adapter(adapter) do
    cond do
      not (is_atom(adapter) and Code.ensure_loaded?(adapter)) ->
        {:error, :managed_inference_adapter_unavailable}

      Elixir.Inference.Adapter.credential_mode(adapter) != :managed_materialization ->
        {:error, :managed_inference_adapter_required}

      true ->
        :ok
    end
  end

  defp managed_authority_projection(call_plan, credential_mode, provider_refs) do
    context = credential_mode.context
    request = credential_mode.request

    projection = %{
      authority_ref: request.authority_ref,
      execution_context_ref: context_value(context, :execution_context_ref),
      adapter_ref: "gemini_ex",
      provider_ref: "gemini",
      connector_instance_ref: context_value(context, :connector_instance_ref),
      connector_binding_ref: context_value(context, :connector_binding_ref),
      endpoint_ref: request.endpoint_ref,
      provider_account_ref: request.account.account_ref,
      credential_ref: context_value(context, :credential_ref),
      credential_handle_ref: context_value(context, :credential_handle_ref),
      credential_lease_ref: request.lease_id,
      target_ref: request.target_ref,
      target_posture_ref: context_value(context, :target_posture_ref),
      attach_grant_ref: context_value(context, :attach_grant_ref),
      operation_policy_ref: context_value(context, :operation_policy_ref),
      model_ref: context_value(context, :model_ref) || Contracts.get(call_plan.model_spec, :id),
      model_account_ref: request.account.account_ref,
      service_identity_ref: context_value(context, :service_identity_ref),
      service_principal_ref: context_value(context, :service_principal_ref)
    }

    required = Map.keys(projection)
    missing = Enum.reject(required, &present_string?(Map.get(projection, &1)))

    if missing == [] do
      {:ok, Map.merge(projection, provider_refs)}
    else
      {:error, {:managed_authority_refs_missing, missing}}
    end
  end

  defp managed_request_opts(call_plan) do
    call_plan.options
    |> Map.take([:temperature, :top_p, :max_tokens])
    |> put_default_token_budget()
    |> Map.put(:id, context_value(call_plan.observability, :span_id))
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp managed_response_summary(response, response_text, finish_reason, usage) do
    %{
      id: response.id,
      provider: response.provider,
      model: response.model,
      finish_reason: finish_reason,
      usage: usage,
      text: response_text
    }
    |> Contracts.dump_json_safe!()
  end

  defp consume_managed_stream(enumerable) do
    initial = %{
      parts: [],
      checkpoints: [],
      chunk_count: 0,
      byte_count: 0,
      finish_reason: :stop,
      usage: nil
    }

    enumerable
    |> Enum.reduce_while({:ok, initial}, fn event, {:ok, acc} ->
      case managed_stream_event(event, acc) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:done, next} -> {:halt, {:ok, next}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, state} ->
        {:ok,
         state
         |> Map.put(:text, state.parts |> Enum.reverse() |> IO.iodata_to_binary())
         |> Map.delete(:parts)}

      {:error, _reason} = error ->
        error
    end
  end

  defp managed_stream_event(%Elixir.Inference.StreamEvent{type: :delta, data: data}, acc) do
    text = stream_delta_text(data)
    chunk_count = acc.chunk_count + 1
    byte_count = acc.byte_count + byte_size(text)

    {:ok,
     %{
       acc
       | parts: [text | acc.parts],
         chunk_count: chunk_count,
         byte_count: byte_count,
         checkpoints: acc.checkpoints ++ [%{chunk_count: chunk_count, byte_count: byte_count}]
     }}
  end

  defp managed_stream_event(%Elixir.Inference.StreamEvent{type: :done, data: %{} = data}, acc) do
    with {:ok, finish_reason} <-
           normalize_managed_finish_reason(
             context_value(data, :finish_reason) || acc.finish_reason
           ) do
      {:done,
       %{
         acc
         | finish_reason: finish_reason,
           usage: context_value(data, :usage) || acc.usage
       }}
    end
  end

  defp managed_stream_event(%Elixir.Inference.StreamEvent{type: :done}, _acc),
    do: {:error, :invalid_managed_provider_done_event}

  defp managed_stream_event(
         %Elixir.Inference.StreamEvent{
           type: :error,
           data: %Elixir.Inference.Error{reason: reason}
         },
         _acc
       )
       when is_atom(reason),
       do: {:error, reason}

  defp managed_stream_event(%Elixir.Inference.StreamEvent{type: :error}, _acc),
    do: {:error, :managed_provider_stream_failed}

  defp managed_stream_event(%Elixir.Inference.StreamEvent{}, acc), do: {:ok, acc}
  defp managed_stream_event(_event, _acc), do: {:error, :invalid_managed_provider_stream_event}

  defp normalize_managed_finish_reason(reason) when reason in [nil, :stop, "stop", "STOP"],
    do: {:ok, :stop}

  defp normalize_managed_finish_reason(reason)
       when reason in [:length, "length", "MAX_TOKENS"],
       do: {:ok, :length}

  defp normalize_managed_finish_reason(_reason),
    do: {:error, :unsupported_managed_provider_finish_reason}

  defp durable_managed_usage(usage) when is_map(usage) do
    reasoning_tokens = Map.get(usage, :thoughts_tokens, Map.get(usage, "thoughts_tokens"))

    usage
    |> Map.drop([:thoughts_tokens, "thoughts_tokens"])
    |> maybe_put(:reasoning_tokens, reasoning_tokens)
  end

  defp durable_managed_usage(_usage), do: nil

  defp stream_delta_text(data) when is_binary(data), do: data
  defp stream_delta_text(%{text: text}) when is_binary(text), do: text
  defp stream_delta_text(%{"text" => text}) when is_binary(text), do: text
  defp stream_delta_text(_data), do: ""

  defp managed_stream_checkpoints(_stream_id, :disabled, _checkpoints), do: []

  defp managed_stream_checkpoints(stream_id, _policy, checkpoints) do
    Enum.map(checkpoints, fn checkpoint ->
      Map.merge(checkpoint, %{stream_id: stream_id, content_artifact_id: nil})
    end)
  end

  defp required_string_option(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      {:ok, _value} -> {:error, {:invalid_managed_inference_option, key}}
      :error -> {:error, {:managed_inference_option_required, key}}
    end
  end

  defp normalize_managed_execution({:ok, %{status: :ok, execution: execution}}),
    do: {:ok, execution}

  defp normalize_managed_execution({:ok, %{status: :error, error_class: error_class}}),
    do: {:error, {:managed_provider_call_failed, error_class}}

  defp normalize_managed_execution({:error, _reason} = error), do: error

  defp safe_error_class(reason) when is_atom(reason), do: reason
  defp safe_error_class({reason, _detail}) when is_atom(reason), do: reason
  defp safe_error_class(_reason), do: :managed_provider_error

  defp context_value(context, key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp safe_kind(%{__struct__: module}) when is_atom(module), do: module
  defp safe_kind(value) when is_atom(value), do: value
  defp safe_kind(_value), do: :redacted

  defp missing_ref(missing, _field, value) when is_binary(value) and value != "", do: missing
  defp missing_ref(missing, field, _value), do: [field | missing]

  defp map_or_empty(nil), do: %{}
  defp map_or_empty(%{} = value), do: Map.new(value)
end
