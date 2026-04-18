defmodule Jido.Integration.V2.ControlPlane.InferenceRecorder do
  @moduledoc false

  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.BackendManifest
  alias Jido.Integration.V2.CompatibilityResult
  alias Jido.Integration.V2.ConsumerManifest
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane.ClaimCheck
  alias Jido.Integration.V2.ControlPlane.Stores
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.EndpointDescriptor
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.InferenceExecutionContext
  alias Jido.Integration.V2.InferenceRequest
  alias Jido.Integration.V2.InferenceResult
  alias Jido.Integration.V2.LeaseRef
  alias Jido.Integration.V2.Run

  @inference_capability_id "inference.execute"
  @inference_connector_id "inference"

  @spec inference_capability_id() :: String.t()
  def inference_capability_id, do: @inference_capability_id

  @spec inference_connector_id() :: String.t()
  def inference_connector_id, do: @inference_connector_id

  @spec record(map()) ::
          {:ok, %{run: Run.t(), attempt: Attempt.t()}} | {:error, Exception.t() | term()}
  def record(spec) when is_map(spec) do
    with {:ok, normalized_spec} <- normalize_spec(spec),
         {:ok, run} <- build_run(normalized_spec),
         :ok <- Stores.run_store().put_run(run),
         {:ok, attempt} <- build_attempt(normalized_spec, run),
         :ok <- Stores.attempt_store().put_attempt(attempt),
         :ok <- append_events(run, attempt, normalized_spec) do
      {:ok, %{run: fetch_run!(run.run_id), attempt: fetch_attempt!(attempt.attempt_id)}}
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  def record(spec) do
    {:error,
     ArgumentError.exception("inference record spec must be a map, got: #{inspect(spec)}")}
  end

  @spec inference_review_summary(Run.t(), Attempt.t() | nil) :: {:ok, map()} | :error
  def inference_review_summary(%Run{} = run, %Attempt{} = attempt) do
    input = resolved_payload(run.input, Map.get(run, :input_payload_ref))
    {output_payload, output_ref} = output_source(run, attempt)
    output = resolved_payload(output_payload, output_ref)

    if inference_payload?(input) or inference_payload?(output) do
      capability = capability_summary(run, attempt, output)

      {:ok,
       %{
         connector: connector_summary(capability),
         capability: capability
       }}
    else
      :error
    end
  end

  def inference_review_summary(%Run{} = run, nil) do
    inference_review_summary(
      run,
      Attempt.new!(%{
        run_id: run.run_id,
        attempt: 1,
        runtime_class: run.runtime_class,
        status: :accepted
      })
    )
  rescue
    _ -> :error
  end

  defp normalize_spec(spec) do
    request = normalize_contract!(InferenceRequest, Map.fetch!(spec, :request), :request)
    context = normalize_contract!(InferenceExecutionContext, Map.fetch!(spec, :context), :context)

    consumer_manifest =
      normalize_contract!(
        ConsumerManifest,
        Map.fetch!(spec, :consumer_manifest),
        :consumer_manifest
      )

    compatibility_result =
      normalize_contract!(
        CompatibilityResult,
        Map.fetch!(spec, :compatibility_result),
        :compatibility_result
      )

    result = normalize_contract!(InferenceResult, Map.fetch!(spec, :result), :result)

    endpoint_descriptor =
      normalize_optional_contract(
        spec[:endpoint_descriptor],
        EndpointDescriptor,
        :endpoint_descriptor
      )

    backend_manifest =
      normalize_optional_contract(spec[:backend_manifest], BackendManifest, :backend_manifest)

    lease_ref = normalize_optional_contract(spec[:lease_ref], LeaseRef, :lease_ref)
    stream = normalize_stream(spec[:stream], request, context, result)

    validate_identity_alignment!(context, result)
    validate_endpoint_alignment!(endpoint_descriptor, result)
    validate_lease_alignment!(lease_ref, endpoint_descriptor)

    {:ok,
     %{
       request: request,
       context: context,
       consumer_manifest: consumer_manifest,
       compatibility_result: compatibility_result,
       endpoint_descriptor: endpoint_descriptor,
       backend_manifest: backend_manifest,
       lease_ref: lease_ref,
       stream: stream,
       result: result
     }}
  rescue
    error in KeyError ->
      {:error,
       ArgumentError.exception("missing required inference record field: #{inspect(error.key)}")}

    error in ArgumentError ->
      {:error, error}
  end

  defp build_run(spec) do
    runtime_class = legacy_runtime_class(spec.request)
    trace_id = trace_id(spec)

    with {:ok, staged_input} <-
           stage_payload(run_input(spec),
             payload_kind: :run_input,
             trace_id: trace_id,
             redaction_class: "inference_run_input"
           ),
         {:ok, staged_result} <-
           stage_payload(run_result(spec),
             payload_kind: :run_result,
             trace_id: trace_id,
             redaction_class: "inference_run_result"
           ) do
      Run.new(%{
        run_id: spec.context.run_id,
        capability_id: @inference_capability_id,
        runtime_class: runtime_class,
        status: terminal_run_status(spec.result),
        input: staged_input.payload,
        input_payload_ref: staged_input.payload_ref,
        credential_ref: inference_credential_ref(),
        target_id: nil,
        result: staged_result.payload,
        result_payload_ref: staged_result.payload_ref
      })
    end
  end

  defp build_attempt(spec, run) do
    with {:ok, staged_output} <-
           stage_payload(attempt_output(spec),
             payload_kind: :attempt_output,
             trace_id: trace_id(spec),
             redaction_class: "inference_attempt_output"
           ) do
      Attempt.new(%{
        attempt_id: spec.context.attempt_id,
        run_id: run.run_id,
        attempt: Contracts.attempt_from_id!(run.run_id, spec.context.attempt_id),
        aggregator_id: "inference_control_plane",
        aggregator_epoch: 1,
        runtime_class: run.runtime_class,
        status: terminal_attempt_status(spec.result),
        credential_lease_id: nil,
        target_id: nil,
        runtime_ref_id: spec.endpoint_descriptor && spec.endpoint_descriptor.source_runtime_ref,
        output: staged_output.payload,
        output_payload_ref: staged_output.payload_ref
      })
    end
  end

  defp append_events(run, attempt, spec) do
    event_store = Stores.event_store()
    start_seq = event_store.next_seq(run.run_id, attempt.attempt_id)

    with {:ok, events} <- build_events(run, attempt, spec, start_seq) do
      event_store.append_events(events,
        aggregator_id: attempt.aggregator_id,
        aggregator_epoch: attempt.aggregator_epoch
      )
    end
  end

  defp build_events(run, attempt, spec, start_seq) do
    spec
    |> event_specs()
    |> Enum.with_index(start_seq)
    |> Enum.reduce_while({:ok, []}, fn {event_spec, seq}, {:ok, acc} ->
      case stage_payload(
             Map.fetch!(event_spec, :payload),
             payload_kind: "event:#{event_spec.type}",
             trace_id: trace_id(spec),
             redaction_class: "inference_event_payload"
           ) do
        {:ok, staged_payload} ->
          event =
            Event.new!(%{
              event_id: Contracts.event_id(run.run_id, attempt.attempt_id, seq),
              run_id: run.run_id,
              attempt: attempt.attempt,
              attempt_id: attempt.attempt_id,
              seq: seq,
              type: event_spec.type,
              stream: Map.get(event_spec, :stream, :system),
              level: Map.get(event_spec, :level, :info),
              payload: staged_payload.payload,
              payload_ref: staged_payload.payload_ref,
              trace: %{trace_id: trace_id(spec)},
              target_id: nil,
              runtime_ref_id:
                spec.endpoint_descriptor && spec.endpoint_descriptor.source_runtime_ref
            })

          {:cont, {:ok, acc ++ [event]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp event_specs(spec) do
    base_events = [
      %{
        type: "inference.request_admitted",
        payload: %{
          request_id: spec.request.request_id,
          operation: spec.request.operation,
          stream?: spec.request.stream?,
          target_class: resolved_target_class(spec)
        }
      },
      %{
        type: "inference.attempt_started",
        payload: %{
          attempt_id: spec.context.attempt_id,
          runtime_kind: resolved_runtime_kind(spec),
          management_mode: resolved_management_mode(spec)
        }
      },
      %{
        type: "inference.compatibility_evaluated",
        payload: %{
          compatible?: spec.compatibility_result.compatible?,
          reason: spec.compatibility_result.reason,
          consumer: spec.consumer_manifest.consumer,
          backend: spec.backend_manifest && spec.backend_manifest.backend
        }
      },
      %{
        type: "inference.target_resolved",
        payload: %{
          endpoint_id: spec.endpoint_descriptor && spec.endpoint_descriptor.endpoint_id,
          target_class: resolved_target_class(spec),
          protocol: resolved_protocol(spec),
          source_runtime: resolved_source_runtime(spec),
          lease_ref: resolved_lease_ref(spec)
        }
      }
    ]

    base_events ++ stream_event_specs(spec) ++ [terminal_event_spec(spec)]
  end

  defp stream_event_specs(%{stream: nil}), do: []

  defp stream_event_specs(%{stream: stream}) do
    opened =
      %{
        type: "inference.stream_opened",
        payload: %{
          stream_id: stream.opened.stream_id,
          protocol: stream.opened.protocol,
          checkpoint_policy: stream.opened.checkpoint_policy
        }
      }

    checkpoints =
      Enum.map(stream.checkpoints, fn checkpoint ->
        %{
          type: "inference.stream_checkpoint",
          payload: %{
            stream_id: checkpoint.stream_id,
            chunk_count: checkpoint.chunk_count,
            byte_count: checkpoint.byte_count,
            content_artifact_id: checkpoint.content_artifact_id
          }
        }
      end)

    closed =
      %{
        type: "inference.stream_closed",
        payload: %{
          stream_id: stream.closed.stream_id,
          finish_reason: stream.closed.finish_reason,
          chunk_count: stream.closed.chunk_count,
          byte_count: stream.closed.byte_count
        }
      }

    [opened] ++ checkpoints ++ [closed]
  end

  defp terminal_event_spec(spec) do
    %{
      type:
        case spec.result.status do
          :ok -> "inference.attempt_completed"
          :error -> "inference.attempt_failed"
          :cancelled -> "inference.attempt_cancelled"
        end,
      payload: %{
        status: spec.result.status,
        finish_reason: spec.result.finish_reason,
        usage: spec.result.usage,
        error: spec.result.error
      }
    }
  end

  defp run_input(spec) do
    %{
      "contract_version" => Contracts.inference_contract_version(),
      "request" => InferenceRequest.dump(spec.request),
      "context" => InferenceExecutionContext.dump(spec.context),
      "consumer_manifest" => ConsumerManifest.dump(spec.consumer_manifest),
      "backend_manifest" => maybe_dump(spec.backend_manifest),
      "lease_ref" => maybe_dump(spec.lease_ref),
      "phase" => "phase_1_inference_runtime"
    }
    |> Contracts.dump_json_safe!()
  end

  defp run_result(spec) do
    %{
      "contract_version" => Contracts.inference_contract_version(),
      "runtime_kind" => resolved_runtime_kind(spec),
      "management_mode" => resolved_management_mode(spec),
      "target_class" => resolved_target_class(spec),
      "inference_result" => InferenceResult.dump(spec.result),
      "compatibility_result" => CompatibilityResult.dump(spec.compatibility_result),
      "endpoint_descriptor" => maybe_dump(spec.endpoint_descriptor),
      "stream" => spec.stream
    }
    |> Contracts.dump_json_safe!()
  end

  defp attempt_output(spec) do
    %{
      "contract_version" => Contracts.inference_contract_version(),
      "runtime_kind" => resolved_runtime_kind(spec),
      "management_mode" => resolved_management_mode(spec),
      "target_class" => resolved_target_class(spec),
      "consumer_manifest" => ConsumerManifest.dump(spec.consumer_manifest),
      "backend_manifest" => maybe_dump(spec.backend_manifest),
      "endpoint_descriptor" => maybe_dump(spec.endpoint_descriptor),
      "lease_ref" => maybe_dump(spec.lease_ref),
      "compatibility_result" => CompatibilityResult.dump(spec.compatibility_result),
      "inference_result" => InferenceResult.dump(spec.result),
      "stream" => spec.stream
    }
    |> Contracts.dump_json_safe!()
  end

  defp connector_summary(capability) do
    %{
      connector_id: @inference_connector_id,
      display_name: "Inference",
      description: "Live inference runtime with durable control-plane truth",
      category: "inference",
      tags: ["inference", "phase_1"],
      maturity: :experimental,
      publication: :internal,
      auth_type: :none,
      runtime_families: [:inference],
      capability_ids: [@inference_capability_id],
      capabilities: [capability]
    }
  end

  defp capability_summary(run, attempt, output) do
    %{
      capability_id: run.capability_id,
      connector_id: @inference_connector_id,
      runtime_class: attempt.runtime_class,
      kind: :operation,
      transport_profile: :api,
      name: "inference_execute",
      display_name: "Inference Execute",
      description: "Live inference execution with durable review truth",
      required_scopes: [],
      runtime: %{
        family: :inference,
        runtime_kind: normalize_output_runtime_kind(Contracts.get(output, :runtime_kind)),
        management_mode:
          normalize_output_management_mode(Contracts.get(output, :management_mode)),
        target_class: normalize_output_target_class(Contracts.get(output, :target_class))
      },
      consumer_surface: %{
        mode: :connector_local,
        reason: "Live inference runtime"
      }
    }
  end

  defp inference_payload?(%{} = payload) do
    Contracts.get(payload, :contract_version) == Contracts.inference_contract_version() or
      (ClaimCheck.claim_checked?(payload) and
         payload
         |> Map.get(ClaimCheck.metadata_key(), %{})
         |> Map.get("preview", %{})
         |> Contracts.get(:contract_version) == Contracts.inference_contract_version())
  end

  defp inference_payload?(_value), do: false

  defp validate_identity_alignment!(context, result) do
    if context.run_id != result.run_id or context.attempt_id != result.attempt_id do
      raise ArgumentError,
            "context and result identities must align: #{inspect({context.run_id, context.attempt_id, result.run_id, result.attempt_id})}"
    end
  end

  defp validate_endpoint_alignment!(nil, _result), do: :ok

  defp validate_endpoint_alignment!(endpoint_descriptor, result) do
    if result.endpoint_id != nil and result.endpoint_id != endpoint_descriptor.endpoint_id do
      raise ArgumentError,
            "result.endpoint_id must match endpoint_descriptor.endpoint_id"
    end
  end

  defp validate_lease_alignment!(nil, _endpoint_descriptor), do: :ok
  defp validate_lease_alignment!(_lease_ref, nil), do: :ok

  defp validate_lease_alignment!(lease_ref, endpoint_descriptor) do
    if endpoint_descriptor.lease_ref != nil and
         endpoint_descriptor.lease_ref != lease_ref.lease_ref do
      raise ArgumentError, "lease_ref must match endpoint_descriptor.lease_ref"
    end
  end

  defp normalize_stream(nil, request, _context, result) do
    if request.stream? or result.streaming? do
      raise ArgumentError, "streaming requests must include stream lifecycle truth"
    end

    nil
  end

  defp normalize_stream(stream, request, context, result) when is_map(stream) do
    if not (request.stream? and result.streaming?) do
      raise ArgumentError, "stream lifecycle truth is only valid for streaming requests"
    end

    opened = normalize_stream_opened!(Map.fetch!(stream, :opened), context)

    checkpoints =
      Enum.map(
        Map.get(stream, :checkpoints, []),
        &normalize_stream_checkpoint!(&1, opened.stream_id)
      )

    closed = normalize_stream_closed!(Map.fetch!(stream, :closed), opened.stream_id)

    if result.stream_id != nil and result.stream_id != opened.stream_id do
      raise ArgumentError, "result.stream_id must match stream.opened.stream_id"
    end

    %{opened: opened, checkpoints: checkpoints, closed: closed}
  end

  defp normalize_stream(stream, _request, _context, _result) do
    raise ArgumentError, "stream must be a map, got: #{inspect(stream)}"
  end

  defp normalize_stream_opened!(opened, context) when is_map(opened) do
    checkpoint_policy =
      Contracts.validate_inference_checkpoint_policy!(
        Contracts.fetch!(opened, :checkpoint_policy)
      )

    expected_checkpoint_policy =
      context.streaming_policy
      |> Contracts.get(:checkpoint_policy, :disabled)
      |> Contracts.validate_inference_checkpoint_policy!()

    if checkpoint_policy != expected_checkpoint_policy do
      raise ArgumentError,
            "stream.opened.checkpoint_policy must match InferenceExecutionContext.streaming_policy.checkpoint_policy"
    end

    %{
      stream_id:
        Contracts.validate_non_empty_string!(
          Contracts.fetch!(opened, :stream_id),
          "stream.opened.stream_id"
        ),
      protocol: Contracts.validate_inference_protocol!(Contracts.fetch!(opened, :protocol)),
      checkpoint_policy: checkpoint_policy
    }
  end

  defp normalize_stream_opened!(opened, _context) do
    raise ArgumentError, "stream.opened must be a map, got: #{inspect(opened)}"
  end

  defp normalize_stream_checkpoint!(checkpoint, stream_id) when is_map(checkpoint) do
    checkpoint_stream_id =
      Contracts.validate_non_empty_string!(
        Contracts.fetch!(checkpoint, :stream_id),
        "stream.checkpoint.stream_id"
      )

    if checkpoint_stream_id != stream_id do
      raise ArgumentError, "stream checkpoint stream_id must match stream.opened.stream_id"
    end

    %{
      stream_id: checkpoint_stream_id,
      chunk_count:
        normalize_non_negative_integer!(
          Contracts.fetch!(checkpoint, :chunk_count),
          "stream.checkpoint.chunk_count"
        ),
      byte_count:
        normalize_non_negative_integer!(
          Contracts.fetch!(checkpoint, :byte_count),
          "stream.checkpoint.byte_count"
        ),
      content_artifact_id:
        normalize_optional_string(
          Contracts.get(checkpoint, :content_artifact_id),
          "stream.checkpoint.content_artifact_id"
        )
    }
  end

  defp normalize_stream_checkpoint!(checkpoint, _stream_id) do
    raise ArgumentError, "stream checkpoint must be a map, got: #{inspect(checkpoint)}"
  end

  defp normalize_stream_closed!(closed, stream_id) when is_map(closed) do
    closed_stream_id =
      Contracts.validate_non_empty_string!(
        Contracts.fetch!(closed, :stream_id),
        "stream.closed.stream_id"
      )

    if closed_stream_id != stream_id do
      raise ArgumentError, "stream.closed.stream_id must match stream.opened.stream_id"
    end

    %{
      stream_id: closed_stream_id,
      finish_reason:
        Contracts.normalize_atomish!(
          Contracts.get(closed, :finish_reason),
          "stream.closed.finish_reason"
        ),
      chunk_count:
        normalize_non_negative_integer!(
          Contracts.fetch!(closed, :chunk_count),
          "stream.closed.chunk_count"
        ),
      byte_count:
        normalize_non_negative_integer!(
          Contracts.fetch!(closed, :byte_count),
          "stream.closed.byte_count"
        )
    }
  end

  defp normalize_stream_closed!(closed, _stream_id) do
    raise ArgumentError, "stream.closed must be a map, got: #{inspect(closed)}"
  end

  defp normalize_non_negative_integer!(value, _field_name) when is_integer(value) and value >= 0,
    do: value

  defp normalize_non_negative_integer!(value, field_name) do
    raise ArgumentError, "#{field_name} must be a non-negative integer, got: #{inspect(value)}"
  end

  defp normalize_optional_string(nil, _field_name), do: nil

  defp normalize_optional_string(value, field_name) do
    Contracts.validate_non_empty_string!(value, field_name)
  end

  defp normalize_contract!(module, %module{} = value, _field_name), do: value
  defp normalize_contract!(module, value, _field_name), do: module.new!(value)

  defp normalize_optional_contract(nil, _module, _field_name), do: nil
  defp normalize_optional_contract(%module{} = value, module, _field_name), do: value
  defp normalize_optional_contract(value, module, _field_name), do: module.new!(value)

  defp terminal_run_status(%InferenceResult{status: :ok}), do: :completed
  defp terminal_run_status(%InferenceResult{status: :error}), do: :failed
  defp terminal_run_status(%InferenceResult{status: :cancelled}), do: :failed

  defp terminal_attempt_status(%InferenceResult{status: :ok}), do: :completed
  defp terminal_attempt_status(%InferenceResult{status: :error}), do: :failed
  defp terminal_attempt_status(%InferenceResult{status: :cancelled}), do: :failed

  defp legacy_runtime_class(%InferenceRequest{stream?: true}), do: :stream
  defp legacy_runtime_class(%InferenceRequest{}), do: :direct

  defp resolved_runtime_kind(spec) do
    spec.compatibility_result.resolved_runtime_kind ||
      (spec.endpoint_descriptor && spec.endpoint_descriptor.runtime_kind) ||
      :client
  end

  defp resolved_management_mode(spec) do
    spec.compatibility_result.resolved_management_mode ||
      (spec.endpoint_descriptor && spec.endpoint_descriptor.management_mode) ||
      :provider_managed
  end

  defp resolved_target_class(spec) do
    (spec.endpoint_descriptor && spec.endpoint_descriptor.target_class) || :cloud_provider
  end

  defp resolved_protocol(spec) do
    spec.compatibility_result.resolved_protocol ||
      (spec.endpoint_descriptor && spec.endpoint_descriptor.protocol)
  end

  defp resolved_source_runtime(spec) do
    (spec.endpoint_descriptor && spec.endpoint_descriptor.source_runtime) || :req_llm
  end

  defp resolved_lease_ref(spec) do
    (spec.lease_ref && spec.lease_ref.lease_ref) ||
      (spec.endpoint_descriptor && spec.endpoint_descriptor.lease_ref)
  end

  defp stage_payload(payload, opts) do
    ClaimCheck.prepare_json(payload, opts)
  end

  defp resolved_payload(payload, payload_ref) do
    case ClaimCheck.resolve_json(payload || %{}, payload_ref) do
      {:ok, resolved} -> resolved
      {:error, _reason} -> payload || %{}
    end
  end

  defp output_source(run, attempt) do
    if is_nil(attempt.output) and is_nil(Map.get(attempt, :output_payload_ref)) do
      {run.result || %{}, Map.get(run, :result_payload_ref)}
    else
      {attempt.output || %{}, Map.get(attempt, :output_payload_ref)}
    end
  end

  defp trace_id(spec), do: spec.context.observability[:trace_id]

  defp maybe_dump(nil), do: nil
  defp maybe_dump(%BackendManifest{} = manifest), do: BackendManifest.dump(manifest)
  defp maybe_dump(%EndpointDescriptor{} = descriptor), do: EndpointDescriptor.dump(descriptor)
  defp maybe_dump(%LeaseRef{} = lease_ref), do: LeaseRef.dump(lease_ref)

  defp normalize_output_runtime_kind(nil), do: nil
  defp normalize_output_runtime_kind(value), do: Contracts.validate_runtime_kind!(value)

  defp normalize_output_management_mode(nil), do: nil
  defp normalize_output_management_mode(value), do: Contracts.validate_management_mode!(value)

  defp normalize_output_target_class(nil), do: nil
  defp normalize_output_target_class(value), do: Contracts.validate_inference_target_class!(value)

  defp inference_credential_ref do
    CredentialRef.new!(%{
      id: "cred-inference",
      subject: "inference",
      scopes: [],
      metadata: %{proof: "phase_0"}
    })
  end

  defp fetch_run!(run_id) do
    case Stores.run_store().fetch_run(run_id) do
      {:ok, run} -> run
      :error -> raise KeyError, key: run_id, term: :run
    end
  end

  defp fetch_attempt!(attempt_id) do
    case Stores.attempt_store().fetch_attempt(attempt_id) do
      {:ok, attempt} -> attempt
      :error -> raise KeyError, key: attempt_id, term: :attempt
    end
  end
end
