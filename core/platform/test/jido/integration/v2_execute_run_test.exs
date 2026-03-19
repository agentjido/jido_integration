defmodule Jido.Integration.V2ExecuteRunTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec

  defmodule RetryHandler do
    def run(input, context) do
      fail_attempts = Map.get(input, :fail_attempts, 0)
      value = Map.get(input, :value, "ok")

      if context.attempt <= fail_attempts do
        {:error, {:retryable_failure, context.attempt}, %{value: value, attempt: context.attempt}}
      else
        {:ok, %{value: value, attempt: context.attempt}}
      end
    end
  end

  defmodule RetryConnector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "platform_retry",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :none,
            install: %{required: false},
            reauth: %{supported: false},
            requested_scopes: [],
            lease_fields: [],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "Platform Retry",
            description: "Retry test connector",
            category: "test",
            tags: ["retry"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [
          OperationSpec.new!(%{
            operation_id: "platform.retry.echo",
            name: "retry_echo",
            display_name: "Retry echo",
            description: "Retries a direct operation",
            runtime_class: :direct,
            transport_mode: :action,
            handler: RetryHandler,
            input_schema: Zoi.map(description: "Retry input"),
            output_schema: Zoi.map(description: "Retry output"),
            permissions: %{required_scopes: []},
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: ["platform.retry.echo"]
              }
            },
            upstream: %{transport: :action},
            consumer_surface: %{
              mode: :connector_local,
              reason: "Platform retry proofs stay connector-local"
            },
            schema_policy: %{
              input: :passthrough,
              output: :passthrough,
              justification:
                "Retry test connector uses passthrough payloads because it is not part of the normalized common consumer surface"
            },
            jido: %{action: %{name: "platform_retry_echo"}}
          })
        ],
        triggers: [],
        runtime_families: [:direct]
      })
    end
  end

  setup do
    V2.reset!()
    assert :ok = V2.register_connector(RetryConnector)

    on_exit(fn ->
      V2.reset!()
    end)

    :ok
  end

  test "execute_run/3 replays a failed run as a new attempt through the public facade" do
    assert {:error, failed} =
             V2.invoke("platform.retry.echo", %{value: "stable", fail_attempts: 1},
               actor_id: "platform-test",
               tenant_id: "tenant-1",
               environment: :prod,
               allowed_operations: ["platform.retry.echo"]
             )

    assert failed.run.status == :failed
    assert failed.attempt.attempt == 1

    assert {:ok, retried} =
             V2.execute_run(failed.run.run_id, 2,
               actor_id: "platform-test",
               tenant_id: "tenant-1",
               environment: :prod,
               allowed_operations: ["platform.retry.echo"]
             )

    assert retried.run.run_id == failed.run.run_id
    assert retried.run.status == :completed
    assert retried.attempt.attempt == 2
    assert retried.attempt.status == :completed
    assert retried.output == %{value: "stable", attempt: 2}
  end
end
