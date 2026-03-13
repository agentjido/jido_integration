defmodule Jido.Integration.Test.TestAdapter do
  @moduledoc """
  Minimal test adapter implementing the Adapter behaviour.
  Used in registry and integration tests.
  """

  @behaviour Jido.Integration.Adapter

  alias Jido.Integration.{Error, Manifest}

  @impl true
  def id, do: "test_adapter"

  @impl true
  def manifest do
    Manifest.new!(%{
      "id" => "test_adapter",
      "display_name" => "Test Adapter",
      "vendor" => "Jido Test",
      "domain" => "protocol",
      "version" => "0.1.0",
      "quality_tier" => "bronze",
      "telemetry_namespace" => "jido.integration.test_adapter",
      "auth" => [
        %{
          "id" => "none",
          "type" => "none",
          "display_name" => "No Auth",
          "secret_refs" => [],
          "scopes" => [],
          "token_semantics" => "none",
          "rotation_policy" => %{"required" => false, "interval_days" => nil},
          "tenant_binding" => "tenant_only",
          "health_check" => %{"enabled" => false, "interval_s" => 3600}
        }
      ],
      "operations" => [
        %{
          "id" => "test.ping",
          "summary" => "Test ping operation",
          "input_schema" => %{"type" => "object"},
          "output_schema" => %{"type" => "object"},
          "errors" => [
            %{
              "code" => "test.invalid_request",
              "class" => "invalid_request",
              "retryability" => "terminal"
            }
          ],
          "idempotency" => "optional",
          "timeout_ms" => 5_000,
          "rate_limit" => "gateway_default",
          "required_scopes" => []
        }
      ]
    })
  end

  @impl true
  def validate_config(config), do: {:ok, config}

  @impl true
  def health(_opts), do: {:ok, %{status: :healthy, details: %{}}}

  @impl true
  def run("test.ping", _args, _opts) do
    {:ok, %{"pong" => true, "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()}}
  end

  def run(op, _args, _opts) do
    {:error, Error.new(:unsupported, "Unknown operation: #{op}")}
  end
end
