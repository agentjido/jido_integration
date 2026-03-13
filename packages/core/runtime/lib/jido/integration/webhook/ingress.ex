defmodule Jido.Integration.Webhook.Ingress do
  @moduledoc """
  Webhook ingress pipeline — the control-plane entry point for inbound webhooks.

  Pipeline stages:
  1. route + tenant resolution
  2. signature verification
  3. replay protection
  4. trigger normalization + dispatch

  The ingress path is consumer-backed, but consumer supervision is currently a
  host responsibility. Callers must supply `:dispatch_consumer`; the root
  `:jido_integration` application does not auto-start a default consumer.
  """

  alias Jido.Integration.Auth.{Credential, Server}
  alias Jido.Integration.Dispatch.Consumer
  alias Jido.Integration.{Registry, Telemetry}
  alias Jido.Integration.Trigger.Event
  alias Jido.Integration.Webhook.{Dedupe, Route, Router}

  @default_delivery_headers ["x-github-delivery", "x-delivery-id", "x-request-id", "x-event-id"]
  @default_signature_header "x-hub-signature-256"

  @doc """
  Process an inbound webhook request.

  Expected request fields:
  - `:install_id` or `:connector_id`
  - `:headers`
  - `:raw_body`
  - `:body`
  - optional `:context`

  Required options:
  - `:router`
  - `:dedupe`
  - `:dispatch_consumer`

  Optional options:
  - `:auth_server`
  - `:webhook_secret`
  - `:adapter`

  `:dispatch_consumer` is required by design. Hosts own the consumer process and
  choose its storage, naming, retry policy, and callback registration.
  """
  @spec process(map(), keyword()) ::
          {:ok, map()}
          | {:error,
             :route_not_found
             | :tenant_not_found
             | :ambiguous_route
             | :missing_resolution_key
             | :signature_invalid
             | :duplicate
             | :dispatch_consumer_required
             | :trigger_not_resolved
             | :dispatch_rejected}
  def process(request, opts) do
    router = Keyword.fetch!(opts, :router)
    dedupe = Keyword.fetch!(opts, :dedupe)

    emit_received(request)

    with {:ok, route} <- resolve_route(router, request),
         {:ok, secret} <- resolve_verification_secret(route, request, opts),
         :ok <- verify_signature(request, route, secret),
         {:ok, dedupe_key, ttl_ms} <- ensure_not_duplicate(dedupe, request, route),
         {:ok, adapter} <- resolve_adapter(route, opts),
         {:ok, result} <- dispatch(request, route, adapter, dedupe_key, opts) do
      :ok = Dedupe.mark_seen(dedupe, dedupe_key, ttl_ms: ttl_ms)
      {:ok, result}
    else
      {:error, reason} = error ->
        emit_rejected(reason, request)
        error
    end
  end

  defp resolve_route(router, request) do
    lookup =
      cond do
        Map.has_key?(request, :install_id) ->
          %{install_id: request.install_id, request: request}

        Map.has_key?(request, :connector_id) ->
          %{connector_id: request.connector_id, request: request}

        true ->
          %{}
      end

    case Router.resolve(router, lookup) do
      {:ok, %Route{} = route} ->
        emit_webhook("jido.integration.webhook.routed", request, route)
        {:ok, route}

      {:error, reason} = error ->
        emit_webhook("jido.integration.webhook.route_failed", request, nil, %{
          failure_class: reason
        })

        error
    end
  end

  defp resolve_verification_secret(route, request, opts) do
    case Keyword.get(opts, :webhook_secret) do
      secret when is_binary(secret) ->
        {:ok, secret}

      _ ->
        resolve_route_verification_secret(route, request, opts)
    end
  end

  defp verify_signature(_request, _route, nil), do: :ok

  defp verify_signature(request, route, secret) do
    verification = route.verification || %{}
    sig_header = Map.get(verification, :header, @default_signature_header)

    case get_header(request, sig_header) do
      nil ->
        emit_webhook(
          "jido.integration.webhook.signature_failed",
          request,
          route,
          %{failure_class: :missing_header}
        )

        {:error, :signature_invalid}

      signature ->
        verify_computed_signature(request, route, secret, verification, signature)
    end
  end

  defp ensure_not_duplicate(dedupe, request, route) do
    dedupe_key = delivery_id(request, route) || dedupe_fallback_hash(request, route)
    ttl_ms = route.replay_window_days * 24 * 60 * 60 * 1_000

    if Dedupe.seen?(dedupe, dedupe_key) do
      emit_trigger("jido.integration.trigger.duplicate", request, route)
      {:error, :duplicate}
    else
      {:ok, dedupe_key, ttl_ms}
    end
  end

  defp resolve_adapter(route, opts) do
    case Keyword.get(opts, :adapter) do
      nil ->
        case Registry.lookup(route.connector_id) do
          {:ok, adapter} -> {:ok, adapter}
          {:error, _} -> {:ok, nil}
        end

      adapter ->
        {:ok, adapter}
    end
  end

  defp dispatch(request, route, adapter, dedupe_key, opts) do
    trigger_id = determine_trigger_id(route, adapter)

    with true <- is_binary(trigger_id) or {:error, :trigger_not_resolved},
         {:ok, dispatch_consumer} <- fetch_dispatch_consumer(opts) do
      event = build_trigger_event(request, route, trigger_id, dedupe_key)

      case Consumer.dispatch(dispatch_consumer, dispatch_record(event)) do
        {:ok, run_id} ->
          emit_dispatched(request, route, trigger_id)
          {:ok, accepted_result(route, event, run_id)}

        {:duplicate, run_id} ->
          emit_dispatched(request, route, trigger_id)
          {:ok, accepted_result(route, event, run_id, duplicate: true)}

        {:error, reason} ->
          emit_trigger("jido.integration.trigger.rejected", request, route, %{
            trigger_id: trigger_id,
            failure_class: reason
          })

          {:error, :dispatch_rejected}
      end
    end
  end

  defp resolve_route_verification_secret(route, request, opts) do
    case (route.verification || %{})[:secret_ref] do
      nil ->
        {:ok, nil}

      secret_ref ->
        fetch_route_verification_secret(route, request, opts, secret_ref)
    end
  end

  defp fetch_route_verification_secret(route, request, opts, secret_ref) do
    case Keyword.get(opts, :auth_server) do
      nil ->
        emit_webhook(
          "jido.integration.webhook.signature_failed",
          request,
          route,
          %{failure_class: :secret_not_available}
        )

        {:error, :signature_invalid}

      auth_server ->
        case Server.resolve_credential(auth_server, secret_ref, auth_context(route, request)) do
          {:ok, %Credential{} = credential} ->
            {:ok, Credential.secret_value(credential)}

          _ ->
            emit_webhook(
              "jido.integration.webhook.signature_failed",
              request,
              route,
              %{failure_class: :secret_not_found}
            )

            {:error, :signature_invalid}
        end
    end
  end

  defp verify_computed_signature(request, route, secret, verification, signature) do
    expected =
      "sha256=" <>
        (:crypto.mac(
           :hmac,
           verification_algorithm(verification),
           secret,
           request[:raw_body] || ""
         )
         |> Base.encode16(case: :lower))

    if secure_compare(expected, signature) do
      emit_trigger("jido.integration.trigger.validated", request, route)
      :ok
    else
      emit_webhook(
        "jido.integration.webhook.signature_failed",
        request,
        route,
        %{failure_class: :mismatch}
      )

      {:error, :signature_invalid}
    end
  end

  defp emit_received(request) do
    _ = Telemetry.emit("jido.integration.webhook.received", %{}, base_metadata(request, nil, %{}))
    _ = Telemetry.emit("jido.integration.trigger.received", %{}, base_metadata(request, nil, %{}))
  end

  defp emit_dispatched(request, route, trigger_id) do
    emit_webhook("jido.integration.webhook.dispatched", request, route, %{trigger_id: trigger_id})
    emit_trigger("jido.integration.trigger.dispatched", request, route, %{trigger_id: trigger_id})
  end

  defp emit_rejected(reason, request) do
    _ =
      Telemetry.emit(
        "jido.integration.trigger.rejected",
        %{},
        base_metadata(request, nil, %{failure_class: reason})
      )
  end

  defp emit_webhook(event_name, request, route, extra \\ %{}) do
    _ = Telemetry.emit(event_name, %{}, base_metadata(request, route, extra))
  end

  defp emit_trigger(event_name, request, route, extra \\ %{}) do
    _ = Telemetry.emit(event_name, %{}, base_metadata(request, route, extra))
  end

  defp base_metadata(request, route, extra) do
    context = request[:context] || %{}

    %{
      tenant_id: route && route.tenant_id,
      connector_id: (route && route.connector_id) || request[:connector_id],
      connection_id: route && route.connection_id,
      trigger_id: route && route.trigger_id,
      trace_id: Map.get(context, "trace_id", Map.get(context, :trace_id)),
      span_id: Map.get(context, "span_id", Map.get(context, :span_id)),
      actor_id: request[:actor_id] || Map.get(context, "actor_id", Map.get(context, :actor_id))
    }
    |> Map.merge(extra)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp auth_context(route, request) do
    %{
      connector_id: route.connector_id,
      trace_id: get_in(request, [:context, "trace_id"]),
      span_id: get_in(request, [:context, "span_id"]),
      actor_id: request[:actor_id] || "system:webhook"
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp determine_trigger_id(%Route{trigger_id: trigger_id}, _adapter) when is_binary(trigger_id),
    do: trigger_id

  defp determine_trigger_id(_route, nil), do: nil

  defp determine_trigger_id(route, adapter) do
    triggers = adapter.manifest().triggers

    case triggers do
      [trigger] -> trigger.id
      _ -> "#{route.connector_id}.webhook"
    end
  end

  defp build_trigger_event(request, route, trigger_id, dedupe_key) do
    now = DateTime.utc_now()

    %Event{
      trigger_id: trigger_id,
      event_id: dedupe_key,
      event_time: now,
      received_at: now,
      tenant_id: route.tenant_id,
      connector_id: route.connector_id,
      connection_id: route.connection_id,
      resource_key: dedupe_key,
      payload: %{
        "headers" => request[:headers] || %{},
        "body" => request[:body] || %{},
        "tenant_id" => route.tenant_id,
        "connector_id" => route.connector_id,
        "connection_id" => route.connection_id,
        "trigger_id" => trigger_id
      },
      raw: request[:raw_body],
      dedupe_key: dedupe_key,
      checkpoint: nil,
      trace: trace_context(request, route, dedupe_key)
    }
  end

  defp dispatch_record(%Event{} = event) do
    %{
      dispatch_id: event.event_id,
      idempotency_key: event.dedupe_key,
      tenant_id: event.tenant_id,
      connector_id: event.connector_id,
      trigger_id: event.trigger_id,
      event_id: event.event_id,
      dedupe_key: event.dedupe_key,
      workflow_selector: event.trigger_id,
      payload: Map.from_struct(event),
      trace_context: event.trace
    }
  end

  defp accepted_result(route, %Event{} = event, run_id, opts \\ []) do
    %{
      "status" => "accepted",
      "duplicate" => Keyword.get(opts, :duplicate, false),
      "event_type" =>
        get_in(event.payload, ["headers", "x-github-event"]) ||
          get_in(event.payload, ["headers", "x-event-type"]) ||
          "unknown",
      "delivery_id" => event.dedupe_key,
      "connector_id" => route.connector_id,
      "tenant_id" => route.tenant_id,
      "connection_id" => route.connection_id,
      "trigger_id" => event.trigger_id,
      "event_id" => event.event_id,
      "run_id" => run_id
    }
  end

  defp fetch_dispatch_consumer(opts) do
    case Keyword.get(opts, :dispatch_consumer) do
      nil -> {:error, :dispatch_consumer_required}
      dispatch_consumer -> {:ok, dispatch_consumer}
    end
  end

  defp trace_context(request, route, dedupe_key) do
    context = request[:context] || %{}

    %{
      trace_id: Map.get(context, :trace_id) || Map.get(context, "trace_id"),
      span_id: Map.get(context, :span_id) || Map.get(context, "span_id"),
      correlation_id:
        Map.get(context, :correlation_id) || Map.get(context, "correlation_id") || dedupe_key,
      causation_id: dedupe_key,
      connector_id: route.connector_id,
      tenant_id: route.tenant_id,
      connection_id: route.connection_id
    }
  end

  defp delivery_id(request, route) do
    headers = route.delivery_id_headers ++ @default_delivery_headers
    Enum.find_value(headers, &get_header(request, &1))
  end

  defp dedupe_fallback_hash(request, route) do
    :crypto.hash(:sha256, "#{route.connector_id}:#{route.tenant_id}:#{request[:raw_body] || ""}")
    |> Base.encode16(case: :lower)
  end

  defp get_header(request, header_name) do
    headers = request[:headers] || %{}
    Map.get(headers, header_name) || Map.get(headers, String.downcase(header_name))
  end

  defp verification_algorithm(%{algorithm: :sha1}), do: :sha1
  defp verification_algorithm(_verification), do: :sha256

  defp secure_compare(a, b) when byte_size(a) == byte_size(b), do: :crypto.hash_equals(a, b)
  defp secure_compare(_a, _b), do: false
end
