defmodule Jido.Integration.Webhook.RouterTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Webhook.Router

  import Jido.Integration.Test.IsolatedSetup

  setup do
    {:ok, router} = start_isolated_router()
    %{router: router}
  end

  describe "register_route/2" do
    test "registers a dynamic_per_install route", %{router: router} do
      assert :ok =
               Router.register_route(router, %{
                 connector_id: "github",
                 tenant_id: "tenant_1",
                 install_id: "install_abc",
                 callback_topology: :dynamic_per_install,
                 verification: %{
                   type: :hmac,
                   algorithm: :sha256,
                   secret_ref: "auth:github:tenant_1"
                 }
               })
    end

    test "registers a static_per_app route", %{router: router} do
      assert :ok =
               Router.register_route(router, %{
                 connector_id: "zendesk",
                 callback_topology: :static_per_app,
                 tenant_resolution_key: "account_id",
                 verification: %{type: :hmac, algorithm: :sha256, secret_ref: "auth:zendesk:app"}
               })
    end
  end

  describe "resolve/2 for dynamic_per_install" do
    test "resolves install_id to connector + tenant", %{router: router} do
      Router.register_route(router, %{
        connector_id: "github",
        tenant_id: "tenant_1",
        install_id: "inst_abc",
        callback_topology: :dynamic_per_install,
        verification: %{type: :hmac, algorithm: :sha256, secret_ref: "auth:github:tenant_1"}
      })

      assert {:ok, route} = Router.resolve(router, %{install_id: "inst_abc"})
      assert route.connector_id == "github"
      assert route.tenant_id == "tenant_1"
    end

    test "returns not_found for unknown install_id", %{router: router} do
      assert {:error, :route_not_found} = Router.resolve(router, %{install_id: "nope"})
    end
  end

  describe "resolve/2 for static_per_app" do
    test "resolves connector_id for static routes", %{router: router} do
      Router.register_route(router, %{
        connector_id: "zendesk",
        callback_topology: :static_per_app,
        tenant_resolution_key: "account_id",
        verification: %{type: :hmac, algorithm: :sha256, secret_ref: "auth:zendesk:app"}
      })

      assert {:ok, route} = Router.resolve(router, %{connector_id: "zendesk"})
      assert route.connector_id == "zendesk"
      assert route.tenant_resolution_key == "account_id"
    end

    test "uses tenant_resolution_keys to resolve a specific static route", %{router: router} do
      Router.register_route(router, %{
        connector_id: "zendesk",
        tenant_id: "tenant_a",
        connection_id: "conn_a",
        callback_topology: :static_per_app,
        tenant_resolution_keys: ["body.account_id"],
        tenant_resolution: %{"body.account_id" => "acct_1"},
        verification: %{type: :hmac, algorithm: :sha256, secret_ref: "auth:zendesk:acct_1"}
      })

      Router.register_route(router, %{
        connector_id: "zendesk",
        tenant_id: "tenant_b",
        connection_id: "conn_b",
        callback_topology: :static_per_app,
        tenant_resolution_keys: ["body.account_id"],
        tenant_resolution: %{"body.account_id" => "acct_2"},
        verification: %{type: :hmac, algorithm: :sha256, secret_ref: "auth:zendesk:acct_2"}
      })

      assert {:ok, route} =
               Router.resolve(router, %{
                 connector_id: "zendesk",
                 request: %{body: %{"account_id" => "acct_2"}}
               })

      assert route.tenant_id == "tenant_b"
      assert route.connection_id == "conn_b"
    end

    test "returns missing_resolution_key when a static route cannot be disambiguated", %{
      router: router
    } do
      Router.register_route(router, %{
        connector_id: "zendesk",
        tenant_id: "tenant_a",
        callback_topology: :static_per_app,
        tenant_resolution_keys: ["body.account_id"],
        tenant_resolution: %{"body.account_id" => "acct_1"},
        verification: %{type: :hmac, algorithm: :sha256, secret_ref: "auth:zendesk:acct_1"}
      })

      assert {:error, :missing_resolution_key} =
               Router.resolve(router, %{connector_id: "zendesk", request: %{body: %{}}})
    end
  end

  describe "unregister_route/2" do
    test "removes a route", %{router: router} do
      Router.register_route(router, %{
        connector_id: "github",
        tenant_id: "tenant_1",
        install_id: "inst_del",
        callback_topology: :dynamic_per_install,
        verification: %{type: :hmac}
      })

      assert :ok = Router.unregister_route(router, "inst_del")
      assert {:error, :route_not_found} = Router.resolve(router, %{install_id: "inst_del"})
    end
  end

  describe "list_routes/1" do
    test "lists all registered routes", %{router: router} do
      Router.register_route(router, %{
        connector_id: "github",
        tenant_id: "t1",
        install_id: "i1",
        callback_topology: :dynamic_per_install,
        verification: %{type: :hmac}
      })

      Router.register_route(router, %{
        connector_id: "github",
        tenant_id: "t2",
        install_id: "i2",
        callback_topology: :dynamic_per_install,
        verification: %{type: :hmac}
      })

      routes = Router.list_routes(router)
      assert length(routes) == 2
    end
  end
end
