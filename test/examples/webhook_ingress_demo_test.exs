defmodule Jido.Integration.Examples.WebhookIngressDemoTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.Examples.WebhookIngressDemo
  alias Jido.Integration.Test.TelemetryHandler
  import Jido.Integration.Test.IsolatedSetup

  setup do
    {:ok, router} = start_isolated_router()
    {:ok, dedupe} = start_isolated_dedupe(ttl_ms: 60_000)
    %{router: router, dedupe: dedupe}
  end

  test "full webhook ingress demo runs end-to-end", %{router: router, dedupe: dedupe} do
    attach_ref = "webhook-demo-telemetry-#{System.unique_integer([:positive])}"

    :ok =
      TelemetryHandler.attach_many(
        attach_ref,
        [
          [:jido, :integration, :dispatch, :enqueued],
          [:jido, :integration, :dispatch, :delivered],
          [:jido, :integration, :run, :accepted],
          [:jido, :integration, :run, :started],
          [:jido, :integration, :run, :succeeded]
        ],
        recipient: self(),
        include: [:event, :metadata]
      )

    on_exit(fn -> :telemetry.detach(attach_ref) end)

    result = WebhookIngressDemo.run(router, dedupe)

    assert result.dedup_worked == true
    assert result.signature_check_worked == true
    assert result.route_check_worked == true
    assert result.routes_registered == 1

    # Generic resource-opened event dispatched through the webhook adapter
    assert is_map(result.issue_event)
    # Generic resource-updated event dispatched through the webhook adapter
    assert is_map(result.push_event)

    assert_receive {:telemetry, [:jido, :integration, :dispatch, :enqueued], _}, 500
    assert_receive {:telemetry, [:jido, :integration, :dispatch, :delivered], _}, 500
    assert_receive {:telemetry, [:jido, :integration, :run, :accepted], _}, 500
    assert_receive {:telemetry, [:jido, :integration, :run, :started], _}, 500
    assert_receive {:telemetry, [:jido, :integration, :run, :succeeded], _}, 500
  end
end
