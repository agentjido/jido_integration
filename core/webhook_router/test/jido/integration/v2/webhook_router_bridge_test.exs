defmodule Jido.Integration.V2.WebhookRouterBridgeTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.DispatchRuntime
  alias Jido.Integration.V2.DispatchRuntime.Dispatch
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.WebhookRouter

  defmodule WebhookCapability do
    def run(%{trigger: trigger}, context) do
      {:ok,
       %{
         connector_id: trigger.connector_id,
         trigger_id: trigger.trigger_id,
         attempt: context.attempt,
         external_id: trigger.external_id,
         action: trigger.payload["action"]
       }}
    end
  end

  defmodule TestConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "github",
        capabilities: [
          Capability.new!(%{
            id: "github.issue.ingest",
            connector: "github",
            runtime_class: :direct,
            kind: :trigger,
            transport_profile: :webhook,
            handler: WebhookCapability
          })
        ]
      })
    end
  end

  defmodule ExecuteTriggerHandler do
    @behaviour Jido.Integration.V2.DispatchRuntime.Handler

    @impl true
    def execution_opts(trigger, %{attempt: attempt}) do
      {:ok,
       [
         actor_id: "webhook-router-test",
         tenant_id: trigger.tenant_id,
         allowed_operations: [trigger.capability_id],
         aggregator_id: "webhook_router_test",
         aggregator_epoch: attempt,
         trace_id: "webhook-router-attempt-#{attempt}"
       ]}
    end
  end

  setup do
    runtime_dir = tmp_dir!("dispatch")
    router_dir = tmp_dir!("router")
    ControlPlane.reset!()
    assert :ok = ControlPlane.register_connector(TestConnector)

    {:ok, runtime} =
      DispatchRuntime.start_link(
        name: nil,
        storage_dir: runtime_dir,
        backoff_base_ms: 10,
        backoff_cap_ms: 20
      )

    assert :ok = DispatchRuntime.register_handler(runtime, "issues.opened", ExecuteTriggerHandler)
    {:ok, router} = WebhookRouter.start_link(name: nil, storage_dir: router_dir)

    on_exit(fn ->
      ControlPlane.reset!()
      Process.alive?(runtime) && GenServer.stop(runtime, :normal, 5_000)
      Process.alive?(router) && GenServer.stop(router, :normal, 5_000)
      File.rm_rf!(runtime_dir)
      File.rm_rf!(router_dir)
    end)

    %{runtime: runtime, router: router}
  end

  test "routes a signed webhook through auth secret lookup, ingress admission, and dispatch runtime",
       %{runtime: runtime, router: router} do
    %{install_id: install_id, connection_id: connection_id, credential_ref: credential_ref} =
      install_connection_with_webhook_secret()

    assert {:ok, route} =
             WebhookRouter.register_route(router, %{
               connector_id: "github",
               tenant_id: "tenant-1",
               connection_id: connection_id,
               install_id: install_id,
               trigger_id: "issues.opened",
               capability_id: "github.issue.ingest",
               signal_type: "github.issue.opened",
               signal_source: "/webhooks/github/issues.opened",
               callback_topology: :dynamic_per_install,
               delivery_id_headers: ["x-github-delivery"],
               verification: %{
                 algorithm: :sha256,
                 signature_header: "x-hub-signature-256",
                 secret_ref: %{credential_ref: credential_ref, secret_key: "webhook_secret"}
               },
               validator: {__MODULE__, :validate_issue_opened}
             })

    refute Map.has_key?(route.verification, :secret)

    request = signed_request(install_id, "delivery-accepted", %{action: "opened"})

    assert {:ok, result} =
             WebhookRouter.route_webhook(router, request, dispatch_runtime: runtime)

    assert result.route.route_id == route.route_id
    assert result.definition.connector_id == "github"
    assert result.definition.verification.secret == "super-secret"
    assert result.ingress.status == :accepted
    assert result.dispatch_status == :accepted
    assert result.trigger.external_id == "delivery-accepted"

    completed_dispatch =
      wait_for_dispatch(runtime, result.dispatch.dispatch_id, &(&1.status == :completed))

    assert completed_dispatch.run_id == result.run.run_id
    assert {:ok, %Run{status: :completed}} = ControlPlane.fetch_run(result.run.run_id)

    assert {:ok, %Attempt{attempt: 1, status: :completed}} =
             ControlPlane.fetch_attempt("#{result.run.run_id}:1")
  end

  test "returns explicit route and signature failures", %{runtime: runtime, router: router} do
    assert {:error, error} =
             WebhookRouter.route_webhook(
               router,
               %{install_id: "install-missing", raw_body: "{}", body: %{}, headers: %{}},
               dispatch_runtime: runtime
             )

    assert error.reason == :route_not_found
    assert is_nil(error.route)
    assert is_nil(error.trigger)

    %{install_id: install_id, connection_id: connection_id, credential_ref: credential_ref} =
      install_connection_with_webhook_secret()

    assert {:ok, route} =
             WebhookRouter.register_route(router, %{
               connector_id: "github",
               tenant_id: "tenant-1",
               connection_id: connection_id,
               install_id: install_id,
               trigger_id: "issues.opened",
               capability_id: "github.issue.ingest",
               signal_type: "github.issue.opened",
               signal_source: "/webhooks/github/issues.opened",
               callback_topology: :dynamic_per_install,
               delivery_id_headers: ["x-github-delivery"],
               verification: %{
                 algorithm: :sha256,
                 signature_header: "x-hub-signature-256",
                 secret_ref: %{credential_ref: credential_ref, secret_key: "webhook_secret"}
               },
               validator: {__MODULE__, :validate_issue_opened}
             })

    bad_request =
      signed_request(install_id, "delivery-invalid", %{action: "opened"})
      |> put_in([:headers, "x-hub-signature-256"], "sha256=deadbeef")

    assert {:error, error} =
             WebhookRouter.route_webhook(router, bad_request, dispatch_runtime: runtime)

    assert error.reason == :signature_invalid
    assert error.route.route_id == route.route_id
    assert error.trigger.status == :rejected
  end

  def validate_issue_opened(%{action: "opened"}), do: :ok
  def validate_issue_opened(%{"action" => "opened"}), do: :ok
  def validate_issue_opened(_payload), do: {:error, :missing_action}

  defp install_connection_with_webhook_secret do
    now = ~U[2026-03-12 12:00:00Z]

    assert {:ok, %{install: install, connection: connection}} =
             Auth.start_install("github", "tenant-1", %{
               actor_id: "user-1",
               auth_type: :oauth2,
               subject: "octocat",
               requested_scopes: ["repo"],
               now: now
             })

    assert {:ok, %{credential_ref: credential_ref}} =
             Auth.complete_install(install.install_id, %{
               subject: "octocat",
               granted_scopes: ["repo"],
               secret: %{
                 access_token: "gho-secret",
                 webhook_secret: "super-secret"
               },
               now: now
             })

    %{
      install_id: install.install_id,
      connection_id: connection.connection_id,
      credential_ref: credential_ref
    }
  end

  defp signed_request(install_id, delivery_id, body) do
    raw_body = inspect(body)

    %{
      install_id: install_id,
      raw_body: raw_body,
      body: body,
      headers: %{
        "x-github-delivery" => delivery_id,
        "x-hub-signature-256" => "sha256=" <> Base.encode16(signature(raw_body), case: :lower)
      }
    }
  end

  defp signature(raw_body) do
    :crypto.mac(:hmac, :sha256, "super-secret", raw_body)
  end

  defp wait_for_dispatch(runtime, dispatch_id, predicate, attempts \\ 60)

  defp wait_for_dispatch(_runtime, dispatch_id, _predicate, 0) do
    flunk("dispatch #{dispatch_id} did not reach the expected state")
  end

  defp wait_for_dispatch(runtime, dispatch_id, predicate, attempts) do
    case DispatchRuntime.fetch_dispatch(runtime, dispatch_id) do
      {:ok, %Dispatch{} = dispatch} ->
        if predicate.(dispatch) do
          dispatch
        else
          Process.sleep(25)
          wait_for_dispatch(runtime, dispatch_id, predicate, attempts - 1)
        end

      :error ->
        Process.sleep(25)
        wait_for_dispatch(runtime, dispatch_id, predicate, attempts - 1)
    end
  end

  defp tmp_dir!(prefix) do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_webhook_router_bridge_test_#{prefix}_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
