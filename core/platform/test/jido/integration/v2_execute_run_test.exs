defmodule Jido.Integration.V2ExecuteRunTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Manifest

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
        capabilities: [
          Capability.new!(%{
            id: "platform.retry.echo",
            connector: "platform_retry",
            runtime_class: :direct,
            kind: :operation,
            transport_profile: :action,
            handler: RetryHandler
          })
        ]
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
