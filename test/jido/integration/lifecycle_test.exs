defmodule Jido.Integration.LifecycleTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Auth.{Credential, Server}
  alias Jido.Integration.Dispatch.Consumer
  alias Jido.Integration.Examples.HelloWorld
  alias Jido.Integration.{Operation, Registry}
  alias Jido.Integration.Test.{ScopedTestAdapter, WebhookDispatchHandler, WebhookTestAdapter}
  alias Jido.Integration.Webhook.{Ingress, Router}

  import Jido.Integration.Test.IsolatedSetup

  setup do
    suffix = System.unique_integer([:positive])
    {:ok, auth} = start_isolated_auth_server()
    {:ok, router} = start_isolated_router()
    {:ok, dedupe} = start_isolated_dedupe(ttl_ms: 60_000)
    {:ok, consumer} = start_isolated_consumer([])

    :ok =
      Consumer.register_callback(consumer, "webhook_test.webhook.event", WebhookDispatchHandler)

    {:ok, reg} = Registry.start_link(name: :"lifecycle_reg_#{suffix}")

    %{auth: auth, router: router, dedupe: dedupe, consumer: consumer, registry: reg}
  end

  describe "full OAuth lifecycle: install -> connect -> execute" do
    test "stores credential, resolves at execute time, verifies token used", %{auth: auth} do
      {:ok, install} =
        Server.start_install(auth, ScopedTestAdapter.id(), "tenant_1",
          scopes: ["repo", "read:org"],
          actor_id: "user_1"
        )

      assert {:ok, %{connection_id: connection_id, auth_ref: auth_ref, state: :connected}} =
               Server.handle_callback(
                 auth,
                 ScopedTestAdapter.id(),
                 %{
                   "state" => install.session_state["state"],
                   "credential" => %{
                     access_token: "gho_test_token_123",
                     refresh_token: "ghr_test_refresh_456",
                     expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
                   },
                   "granted_scopes" => ["repo", "read:org", "admin:org"],
                   "actor_id" => "system:callback"
                 },
                 install.session_state
               )

      assert auth_ref == "auth:scoped_test:#{connection_id}"

      assert {:ok, conn} = Server.get_connection(auth, connection_id)
      assert conn.state == :connected

      {:ok, resolved} = Server.resolve_credential(auth, auth_ref, %{connector_id: "scoped_test"})
      assert resolved.access_token == "gho_test_token_123"

      assert {:error, :scope_violation} =
               Server.resolve_credential(auth, auth_ref, %{connector_id: WebhookTestAdapter.id()})

      assert :ok = Server.check_connection_scopes(auth, conn.id, ["repo"])

      assert {:error, %{missing_scopes: ["admin"]}} =
               Server.check_connection_scopes(auth, conn.id, ["admin"])
    end
  end

  describe "full webhook lifecycle: register -> receive -> verify -> dedupe -> dispatch" do
    test "processes webhook through complete pipeline", %{
      router: router,
      dedupe: dedupe,
      auth: auth,
      consumer: consumer
    } do
      {:ok, secret} = Credential.new(%{type: :webhook_secret, key: "lifecycle_webhook_secret"})

      {:ok, secret_ref} =
        Server.store_credential(auth, WebhookTestAdapter.id(), "tenant_1", secret)

      Router.register_route(router, %{
        connector_id: WebhookTestAdapter.id(),
        tenant_id: "tenant_1",
        connection_id: "conn_lifecycle_1",
        install_id: "wh_lifecycle_1",
        trigger_id: "webhook_test.webhook.event",
        callback_topology: :dynamic_per_install,
        verification: %{
          type: :hmac,
          algorithm: :sha256,
          header: "x-signature-256",
          secret_ref: secret_ref
        }
      })

      secret = "lifecycle_webhook_secret"
      body = Jason.encode!(%{"event" => "resource.opened", "resource" => %{"id" => 42}})
      signature = compute_signature(body, secret)

      request = %{
        install_id: "wh_lifecycle_1",
        headers: %{
          "x-signature-256" => signature,
          "x-event-type" => "resource.opened",
          "x-delivery-id" => "lifecycle_delivery_001"
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
      run = wait_for_run(consumer, result["run_id"], &(&1.status == :succeeded))
      assert run.result["event_type"] == "resource.opened"

      assert {:error, :duplicate} =
               Ingress.process(request,
                 router: router,
                 dedupe: dedupe,
                 auth_server: auth,
                 dispatch_consumer: consumer,
                 adapter: WebhookTestAdapter
               )

      bad_request = put_in(request.headers["x-signature-256"], "sha256=tampered")

      bad_request = %{
        bad_request
        | headers: %{bad_request.headers | "x-delivery-id" => "lifecycle_delivery_002"}
      }

      assert {:error, :signature_invalid} =
               Ingress.process(bad_request,
                 router: router,
                 dedupe: dedupe,
                 auth_server: auth,
                 dispatch_consumer: consumer
               )
    end
  end

  describe "scope evolution: read -> upgrade -> write" do
    test "scopes gate operations correctly", %{auth: auth} do
      {:ok, conn} =
        Server.create_connection(auth, ScopedTestAdapter.id(), "tenant_scope",
          scopes: ["read:org"]
        )

      {:ok, _} = Server.transition_connection(auth, conn.id, :installing, "user_1")
      {:ok, _} = Server.transition_connection(auth, conn.id, :connected, "system")

      assert :ok = Server.check_connection_scopes(auth, conn.id, ["read:org"])

      assert {:error, %{missing_scopes: ["repo"]}} =
               Server.check_connection_scopes(auth, conn.id, ["repo"])

      {:ok, _} = Server.transition_connection(auth, conn.id, :reauth_required, "system")

      {:ok, conn2} =
        Server.create_connection(auth, ScopedTestAdapter.id(), "tenant_scope_v2",
          scopes: ["repo", "read:org"]
        )

      {:ok, _} = Server.transition_connection(auth, conn2.id, :installing, "user_1")
      {:ok, _} = Server.transition_connection(auth, conn2.id, :connected, "system")

      assert :ok = Server.check_connection_scopes(auth, conn2.id, ["repo"])
    end
  end

  describe "connection degradation: expire -> refresh fail -> reauth_required" do
    test "refresh failure transitions connection", %{auth: auth} do
      {:ok, conn} = Server.create_connection(auth, ScopedTestAdapter.id(), "tenant_degrade")
      {:ok, _} = Server.transition_connection(auth, conn.id, :installing, "user_1")
      {:ok, _} = Server.transition_connection(auth, conn.id, :connected, "system")

      {:ok, cred} =
        Credential.new(%{
          type: :oauth2,
          access_token: "gho_expired_token",
          refresh_token: "ghr_bad_refresh",
          expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)
        })

      {:ok, ref} = Server.store_credential(auth, ScopedTestAdapter.id(), "tenant_degrade", cred)
      :ok = Server.link_connection(auth, conn.id, ref)

      Server.set_refresh_callback(auth, fn _ref, _rt -> {:error, :invalid_grant} end)

      assert {:error, :refresh_failed} =
               Server.resolve_credential(auth, ref, %{connector_id: ScopedTestAdapter.id()})

      {:ok, updated} = Server.get_connection(auth, conn.id)
      assert updated.state == :reauth_required

      trail_entry = List.last(updated.actor_trail)
      assert trail_entry.from_state == :connected
      assert trail_entry.to_state == :reauth_required
      assert trail_entry.actor_id == "system:refresh_failed"
    end
  end

  describe "hello world with auth server" do
    test "execute ping with no-auth adapter works end-to-end", %{registry: reg} do
      :ok = Registry.register(HelloWorld, server: reg)

      {:ok, adapter} = Registry.lookup("example_ping", server: reg)
      assert adapter == HelloWorld

      envelope = Operation.Envelope.new("ping", %{"message" => "auth lifecycle test"})
      assert {:ok, result} = Jido.Integration.execute(adapter, envelope)
      assert result.result["echo"] == "auth lifecycle test"
    end
  end

  defp compute_signature(body, secret) do
    "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))
  end

  # wait_for_run/3-4 imported from IsolatedSetup (deadline-based, no attempt-count brittleness)
end
