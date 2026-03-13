defmodule Jido.Integration.Webhook.RouteTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Webhook.Route

  test "normalizes route metadata from a map" do
    assert {:ok, route} =
             Route.new(%{
               "connector_id" => "github",
               "tenant_id" => "tenant_1",
               "connection_id" => "conn_1",
               "install_id" => "inst_1",
               "trigger_id" => "github.webhook.push",
               "callback_topology" => "dynamic_per_install",
               "tenant_resolution_key" => "body.account_id",
               "verification" => %{
                 "type" => :hmac,
                 "algorithm" => "sha256",
                 "header" => "X-Hub-Signature-256",
                 "secret_ref" => "auth:github:tenant_1"
               }
             })

    assert route.connector_id == "github"
    assert route.callback_topology == :dynamic_per_install
    assert route.tenant_resolution_keys == ["body.account_id"]
    assert route.verification[:header] == "x-hub-signature-256"
    assert route.verification[:secret_ref] == "auth:github:tenant_1"
  end
end
