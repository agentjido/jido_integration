defmodule Jido.Integration.Examples.WebhookIngressDemo do
  @moduledoc """
  Example: Webhook ingress pipeline using jido_integration.

  Demonstrates the full webhook processing flow:

  1. Register webhook routes
  2. Process inbound webhooks through the pipeline
  3. HMAC signature verification
  4. Deduplication of repeated deliveries
  5. Normalize and enqueue through the durable dispatch consumer

  Uses Router, Dedupe, and Ingress from the webhook infrastructure.

  The demo exercises the final telemetry model:

  - `jido.integration.dispatch.*` for transport events such as enqueue and delivery
  - `jido.integration.run.*` for execution lifecycle events such as accepted and succeeded
  """

  alias Jido.Integration.Auth.{Credential, Server}
  alias Jido.Integration.Dispatch.Consumer
  alias Jido.Integration.Test.{WebhookDispatchHandler, WebhookTestAdapter}
  alias Jido.Integration.Webhook.{Ingress, Router}

  @doc """
  Run the full webhook ingress demo.

  Returns results from each stage for verification. Dispatch transport telemetry
  and run execution telemetry are emitted as the demo flows through the
  consumer.
  """
  def run(router, dedupe, auth_server \\ nil, dispatch_consumer \\ nil) do
    {:ok, auth_server} =
      case auth_server do
        nil -> Server.start_link(name: nil)
        server -> {:ok, server}
      end

    {:ok, dispatch_consumer} =
      case dispatch_consumer do
        nil -> Consumer.start_link(name: nil)
        consumer -> {:ok, consumer}
      end

    :ok =
      Consumer.register_callback(
        dispatch_consumer,
        "webhook_test.webhook.event",
        WebhookDispatchHandler
      )

    webhook_secret = "demo_webhook_secret_#{:crypto.strong_rand_bytes(8) |> Base.encode16()}"
    {:ok, webhook_cred} = Credential.new(%{type: :webhook_secret, key: webhook_secret})

    {:ok, secret_ref} =
      Server.store_credential(auth_server, WebhookTestAdapter.id(), "acme-corp", webhook_cred)

    :ok =
      Router.register_route(router, %{
        connector_id: WebhookTestAdapter.id(),
        tenant_id: "acme-corp",
        connection_id: "conn_demo_1",
        install_id: "demo_install_1",
        trigger_id: "webhook_test.webhook.event",
        callback_topology: :dynamic_per_install,
        verification: %{
          type: :hmac,
          algorithm: :sha256,
          header: "x-signature-256",
          secret_ref: secret_ref
        }
      })

    issue_body =
      Jason.encode!(%{
        "event" => "resource.opened",
        "resource" => %{
          "id" => 42,
          "title" => "Bug: widget fails on Tuesdays",
          "actor" => %{"id" => "octocat"}
        }
      })

    issue_request =
      build_request(
        "demo_install_1",
        issue_body,
        webhook_secret,
        "resource.opened",
        "delivery_issue_001"
      )

    {:ok, issue_result} =
      Ingress.process(issue_request,
        router: router,
        dedupe: dedupe,
        auth_server: auth_server,
        dispatch_consumer: dispatch_consumer,
        adapter: WebhookTestAdapter
      )

    issue_run =
      wait_for_run(dispatch_consumer, issue_result["run_id"], &(&1.status == :succeeded))

    {:error, :duplicate} =
      Ingress.process(issue_request,
        router: router,
        dedupe: dedupe,
        auth_server: auth_server,
        dispatch_consumer: dispatch_consumer,
        adapter: WebhookTestAdapter
      )

    push_body =
      Jason.encode!(%{
        "event" => "resource.updated",
        "changes" => [%{"message" => "fix: handle Tuesday edge case"}]
      })

    push_request =
      build_request(
        "demo_install_1",
        push_body,
        webhook_secret,
        "resource.updated",
        "delivery_push_001"
      )

    {:ok, push_result} =
      Ingress.process(push_request,
        router: router,
        dedupe: dedupe,
        auth_server: auth_server,
        dispatch_consumer: dispatch_consumer,
        adapter: WebhookTestAdapter
      )

    push_run = wait_for_run(dispatch_consumer, push_result["run_id"], &(&1.status == :succeeded))

    tampered_request = put_in(push_request.headers["x-signature-256"], "sha256=tampered")

    tampered_request = %{
      tampered_request
      | headers: Map.put(tampered_request.headers, "x-delivery-id", "delivery_tampered")
    }

    {:error, :signature_invalid} =
      Ingress.process(tampered_request,
        router: router,
        dedupe: dedupe,
        auth_server: auth_server,
        dispatch_consumer: dispatch_consumer
      )

    unknown_request = %{push_request | install_id: "unknown_install"}

    unknown_request = %{
      unknown_request
      | headers: Map.put(unknown_request.headers, "x-delivery-id", "delivery_unknown")
    }

    {:error, :route_not_found} =
      Ingress.process(unknown_request,
        router: router,
        dedupe: dedupe,
        auth_server: auth_server,
        dispatch_consumer: dispatch_consumer
      )

    %{
      issue_event: issue_run.result,
      push_event: push_run.result,
      dedup_worked: true,
      signature_check_worked: true,
      route_check_worked: true,
      routes_registered: length(Router.list_routes(router))
    }
  end

  defp build_request(install_id, body, secret, event_type, delivery_id) do
    signature =
      "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))

    %{
      install_id: install_id,
      headers: %{
        "x-signature-256" => signature,
        "x-event-type" => event_type,
        "x-delivery-id" => delivery_id
      },
      raw_body: body,
      body: Jason.decode!(body)
    }
  end

  defp wait_for_run(consumer, run_id, predicate, attempts \\ 50)

  defp wait_for_run(_consumer, run_id, _predicate, 0) do
    raise "run #{run_id} did not reach expected state"
  end

  defp wait_for_run(consumer, run_id, predicate, attempts) do
    case Consumer.get_run(consumer, run_id) do
      {:ok, run} ->
        if predicate.(run) do
          run
        else
          Process.sleep(10)
          wait_for_run(consumer, run_id, predicate, attempts - 1)
        end

      {:error, :not_found} ->
        Process.sleep(10)
        wait_for_run(consumer, run_id, predicate, attempts - 1)
    end
  end
end
