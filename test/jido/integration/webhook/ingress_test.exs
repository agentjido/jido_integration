defmodule Jido.Integration.Webhook.IngressTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Auth.{Credential, Server}
  alias Jido.Integration.Dispatch.Consumer
  alias Jido.Integration.Test.TelemetryHandler
  alias Jido.Integration.Test.WebhookDispatchHandler
  alias Jido.Integration.Test.WebhookTestAdapter
  alias Jido.Integration.Webhook.{Ingress, Router}

  import Jido.Integration.Test.IsolatedSetup

  setup do
    {:ok, router} = start_isolated_router()
    {:ok, dedupe} = start_isolated_dedupe(ttl_ms: 60_000)
    {:ok, auth} = start_isolated_auth_server()
    {:ok, consumer} = start_isolated_consumer([])

    :ok =
      Consumer.register_callback(consumer, "webhook_test.webhook.event", WebhookDispatchHandler)

    {:ok, cred} = Credential.new(%{type: :webhook_secret, key: "webhook_secret_123"})
    {:ok, auth_ref} = Server.store_credential(auth, WebhookTestAdapter.id(), "tenant_1", cred)

    Router.register_route(router, %{
      connector_id: WebhookTestAdapter.id(),
      tenant_id: "tenant_1",
      connection_id: "conn_wh_1",
      install_id: "inst_wh_1",
      trigger_id: "webhook_test.webhook.event",
      callback_topology: :dynamic_per_install,
      verification: %{
        type: :hmac,
        algorithm: :sha256,
        header: "x-signature-256",
        secret_ref: auth_ref
      }
    })

    %{router: router, dedupe: dedupe, auth: auth, consumer: consumer}
  end

  describe "process/2 happy path" do
    test "routes, verifies via secret_ref, dedupes, and dispatches", %{
      router: router,
      dedupe: dedupe,
      auth: auth,
      consumer: consumer
    } do
      body = Jason.encode!(%{"event" => "resource.opened", "resource" => %{"id" => 1}})
      signature = compute_signature(body, "webhook_secret_123")

      request = %{
        install_id: "inst_wh_1",
        headers: %{
          "x-signature-256" => signature,
          "x-event-type" => "resource.opened",
          "x-delivery-id" => "delivery_001"
        },
        raw_body: body,
        body: Jason.decode!(body)
      }

      assert {:ok, result} =
               Ingress.process(request,
                 router: router,
                 dedupe: dedupe,
                 auth_server: auth,
                 dispatch_consumer: consumer,
                 adapter: WebhookTestAdapter
               )

      assert result["status"] == "accepted"
      assert result["delivery_id"] == "delivery_001"
      run = wait_for_run(consumer, result["run_id"], &(&1.status == :succeeded))
      assert run.result["event_type"] == "resource.opened"
    end

    test "returns normalized payload when no adapter is supplied", %{
      router: router,
      dedupe: dedupe,
      auth: auth,
      consumer: consumer
    } do
      body = "{}"
      signature = compute_signature(body, "webhook_secret_123")

      request = %{
        install_id: "inst_wh_1",
        headers: %{
          "x-signature-256" => signature,
          "x-event-type" => "push",
          "x-delivery-id" => "delivery_norm"
        },
        raw_body: body,
        body: %{}
      }

      assert {:ok, result} =
               Ingress.process(request,
                 router: router,
                 dedupe: dedupe,
                 auth_server: auth,
                 dispatch_consumer: consumer
               )

      assert result["connection_id"] == "conn_wh_1"
      assert result["trigger_id"] == "webhook_test.webhook.event"
      assert result["delivery_id"] == "delivery_norm"
      run = wait_for_run(consumer, result["run_id"], &(&1.status == :succeeded))
      assert run.result["event_type"] == "push"
    end
  end

  describe "process/2 routing errors" do
    test "rejects unknown install_id", %{router: router, dedupe: dedupe, auth: auth} do
      request = %{
        install_id: "inst_unknown",
        headers: %{},
        raw_body: "{}",
        body: %{}
      }

      assert {:error, :route_not_found} =
               Ingress.process(request, router: router, dedupe: dedupe, auth_server: auth)
    end
  end

  describe "process/2 dispatch ownership" do
    test "requires the host to supply a dispatch consumer for accepted ingress", %{
      router: router,
      dedupe: dedupe,
      auth: auth
    } do
      body = "{}"
      signature = compute_signature(body, "webhook_secret_123")

      request = %{
        install_id: "inst_wh_1",
        headers: %{
          "x-signature-256" => signature,
          "x-event-type" => "push",
          "x-delivery-id" => "delivery_missing_consumer"
        },
        raw_body: body,
        body: %{}
      }

      assert {:error, :dispatch_consumer_required} =
               Ingress.process(request,
                 router: router,
                 dedupe: dedupe,
                 auth_server: auth,
                 adapter: WebhookTestAdapter
               )
    end
  end

  describe "process/2 signature verification" do
    test "rejects invalid signature", %{router: router, dedupe: dedupe, auth: auth} do
      request = %{
        install_id: "inst_wh_1",
        headers: %{
          "x-signature-256" => "sha256=invalid",
          "x-event-type" => "push",
          "x-delivery-id" => "delivery_bad_sig"
        },
        raw_body: "{}",
        body: %{}
      }

      assert {:error, :signature_invalid} =
               Ingress.process(request, router: router, dedupe: dedupe, auth_server: auth)
    end
  end

  describe "process/2 deduplication" do
    test "rejects duplicate delivery_id", %{
      router: router,
      dedupe: dedupe,
      auth: auth,
      consumer: consumer
    } do
      body = "{}"
      signature = compute_signature(body, "webhook_secret_123")

      request = %{
        install_id: "inst_wh_1",
        headers: %{
          "x-signature-256" => signature,
          "x-event-type" => "push",
          "x-delivery-id" => "delivery_dup"
        },
        raw_body: body,
        body: %{}
      }

      opts = [
        router: router,
        dedupe: dedupe,
        auth_server: auth,
        dispatch_consumer: consumer,
        adapter: WebhookTestAdapter
      ]

      assert {:ok, _} = Ingress.process(request, opts)
      assert {:error, :duplicate} = Ingress.process(request, opts)
    end

    test "dispatch rejection does not poison the dedupe key", %{
      router: router,
      dedupe: dedupe,
      auth: auth
    } do
      body = "{}"
      signature = compute_signature(body, "webhook_secret_123")

      request = %{
        install_id: "inst_wh_1",
        headers: %{
          "x-signature-256" => signature,
          "x-event-type" => "push",
          "x-delivery-id" => "delivery_retryable"
        },
        raw_body: body,
        body: %{}
      }

      {:ok, consumer} = start_isolated_consumer([])

      opts = [
        router: router,
        dedupe: dedupe,
        auth_server: auth,
        dispatch_consumer: consumer,
        adapter: WebhookTestAdapter
      ]

      assert {:error, :dispatch_rejected} = Ingress.process(request, opts)
      assert {:error, :dispatch_rejected} = Ingress.process(request, opts)

      :ok =
        Consumer.register_callback(consumer, "webhook_test.webhook.event", WebhookDispatchHandler)

      assert {:ok, accepted} = Ingress.process(request, opts)
      assert accepted["delivery_id"] == "delivery_retryable"
    end

    test "falls back to a body hash when delivery headers are missing", %{
      router: router,
      dedupe: dedupe,
      auth: auth,
      consumer: consumer
    } do
      body = Jason.encode!(%{"event" => "resource.opened"})
      signature = compute_signature(body, "webhook_secret_123")

      request = %{
        install_id: "inst_wh_1",
        headers: %{
          "x-signature-256" => signature,
          "x-event-type" => "resource.opened"
        },
        raw_body: body,
        body: Jason.decode!(body)
      }

      opts = [router: router, dedupe: dedupe, auth_server: auth, dispatch_consumer: consumer]

      assert {:ok, _} = Ingress.process(request, opts)
      assert {:error, :duplicate} = Ingress.process(request, opts)
    end
  end

  describe "process/2 telemetry" do
    test "emits webhook.received and webhook.dispatched", %{
      router: router,
      dedupe: dedupe,
      auth: auth,
      consumer: consumer
    } do
      attach_ref = "ingress-tel-#{inspect(make_ref())}"
      pid = self()

      :ok =
        TelemetryHandler.attach_many(
          attach_ref,
          [
            [:jido, :integration, :webhook, :received],
            [:jido, :integration, :webhook, :dispatched]
          ],
          recipient: pid,
          include: [:event, :metadata]
        )

      on_exit(fn -> :telemetry.detach(attach_ref) end)

      body = "{}"
      signature = compute_signature(body, "webhook_secret_123")

      request = %{
        install_id: "inst_wh_1",
        headers: %{
          "x-signature-256" => signature,
          "x-event-type" => "push",
          "x-delivery-id" => "delivery_tel"
        },
        raw_body: body,
        body: %{}
      }

      Ingress.process(request,
        router: router,
        dedupe: dedupe,
        auth_server: auth,
        dispatch_consumer: consumer,
        adapter: WebhookTestAdapter
      )

      assert_receive {:telemetry, [:jido, :integration, :webhook, :received], _}
      assert_receive {:telemetry, [:jido, :integration, :webhook, :dispatched], _}
    end

    test "emits webhook.signature_failed on bad signature", %{
      router: router,
      dedupe: dedupe,
      auth: auth
    } do
      attach_ref = "ingress-sigfail-#{inspect(make_ref())}"
      pid = self()

      :ok =
        TelemetryHandler.attach(
          attach_ref,
          [:jido, :integration, :webhook, :signature_failed],
          recipient: pid
        )

      on_exit(fn -> :telemetry.detach(attach_ref) end)

      request = %{
        install_id: "inst_wh_1",
        headers: %{
          "x-signature-256" => "sha256=bad",
          "x-event-type" => "push",
          "x-delivery-id" => "delivery_sigfail"
        },
        raw_body: "{}",
        body: %{}
      }

      Ingress.process(request, router: router, dedupe: dedupe, auth_server: auth)

      assert_receive {:telemetry, %{connector_id: "webhook_test"}}
    end
  end

  defp compute_signature(body, secret) do
    "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))
  end

  # wait_for_run/3-4 imported from IsolatedSetup (deadline-based, no attempt-count brittleness)
end
