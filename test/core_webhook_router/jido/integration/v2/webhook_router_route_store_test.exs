defmodule Jido.Integration.V2.WebhookRouterRouteStoreTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.TestTmpDir
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.WebhookRouter

  test "registers, fetches, lists, removes, and recovers routes from durable storage" do
    storage_dir = tmp_dir!()
    {:ok, router} = start_router(storage_dir)

    assert {:ok, route} =
             WebhookRouter.register_route(router, dynamic_route_attrs(%{install_id: "install-1"}))

    assert {:ok, fetched_route} = WebhookRouter.fetch_route(router, route.route_id)
    assert fetched_route.route_id == route.route_id
    assert fetched_route.install_id == "install-1"
    assert [%{route_id: route_id}] = WebhookRouter.list_routes(router)
    assert route_id == route.route_id

    stop_router(router)

    {:ok, restarted} = start_router(storage_dir)

    assert {:ok, recovered_route} = WebhookRouter.fetch_route(restarted, route.route_id)
    assert recovered_route.install_id == "install-1"

    assert :ok = WebhookRouter.remove_route(restarted, route.route_id)
    assert :error = WebhookRouter.fetch_route(restarted, route.route_id)
    assert [] = WebhookRouter.list_routes(restarted)
  end

  test "resolves dynamic and static routes by install or connector context" do
    storage_dir = tmp_dir!()
    {:ok, router} = start_router(storage_dir)

    assert {:ok, dynamic_route} =
             WebhookRouter.register_route(
               router,
               dynamic_route_attrs(%{
                 install_id: "install-dynamic",
                 tenant_id: "tenant-dynamic"
               })
             )

    assert {:ok, _} =
             WebhookRouter.register_route(
               router,
               static_route_attrs(%{
                 tenant_id: "tenant-a",
                 connection_id: "connection-a",
                 tenant_resolution: %{"body.account_id" => "acct-1"}
               })
             )

    assert {:ok, _} =
             WebhookRouter.register_route(
               router,
               static_route_attrs(%{
                 tenant_id: "tenant-b",
                 connection_id: "connection-b",
                 tenant_resolution: %{"body.account_id" => "acct-2"}
               })
             )

    assert {:ok, resolved_dynamic} =
             WebhookRouter.resolve_route(router, %{install_id: "install-dynamic"})

    assert resolved_dynamic.route_id == dynamic_route.route_id
    assert resolved_dynamic.tenant_id == "tenant-dynamic"

    assert {:ok, resolved_static} =
             WebhookRouter.resolve_route(router, %{
               connector_id: "zendesk",
               request: %{body: %{"account_id" => "acct-2"}}
             })

    assert resolved_static.tenant_id == "tenant-b"
    assert resolved_static.connection_id == "connection-b"

    assert {:error, :missing_resolution_key} =
             WebhookRouter.resolve_route(router, %{connector_id: "zendesk", request: %{body: %{}}})
  end

  defp start_router(storage_dir) do
    WebhookRouter.start_link(name: nil, storage_dir: storage_dir)
  end

  defp stop_router(router) do
    GenServer.stop(router, :normal, 5_000)
  end

  defp dynamic_route_attrs(overrides) do
    Map.merge(
      %{
        connector_id: "github",
        tenant_id: "tenant-1",
        connection_id: "connection-1",
        install_id: "install-1",
        trigger_id: "github.issue.ingest",
        capability_id: "github.issue.ingest",
        signal_type: "github.issue.opened",
        signal_source: "/ingress/webhook/github/issues.opened",
        callback_topology: :dynamic_per_install,
        delivery_id_headers: ["x-github-delivery"],
        verification: %{
          algorithm: :sha256,
          signature_header: "x-hub-signature-256",
          secret_ref: %{
            credential_ref:
              CredentialRef.new!(%{
                id: "cred-route-dynamic",
                subject: "octocat",
                metadata: %{tenant_id: "tenant-1", connector_id: "github"}
              }),
            secret_key: "webhook_secret"
          }
        }
      },
      overrides
    )
  end

  defp static_route_attrs(overrides) do
    Map.merge(
      %{
        connector_id: "zendesk",
        tenant_id: "tenant-static",
        connection_id: "connection-static",
        trigger_id: "tickets.updated",
        capability_id: "zendesk.ticket.ingest",
        signal_type: "zendesk.ticket.updated",
        signal_source: "/webhooks/zendesk/tickets.updated",
        callback_topology: :static_per_app,
        tenant_resolution_keys: ["body.account_id"],
        tenant_resolution: %{"body.account_id" => "acct-1"},
        delivery_id_headers: ["x-zendesk-delivery"],
        verification: %{
          algorithm: :sha256,
          signature_header: "x-zendesk-signature",
          secret_ref: %{
            credential_ref:
              CredentialRef.new!(%{
                id: "cred-route-static",
                subject: "zendesk-app",
                metadata: %{connector_id: "zendesk"}
              }),
            secret_key: "webhook_secret"
          }
        }
      },
      overrides
    )
  end

  defp tmp_dir! do
    path = TestTmpDir.create!("jido_webhook_router_route_store_test")

    on_exit(fn -> TestTmpDir.cleanup!(path) end)
    path
  end
end
