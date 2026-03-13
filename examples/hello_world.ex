defmodule Jido.Integration.Examples.HelloWorld do
  @moduledoc """
  Hello-world reference connector (doc 046).

  The simplest possible connector proving the factory discipline:
  manifest + adapter + conformance. One operation: `ping` echoes
  input back with connector metadata.

  ## Usage

      # Register
      Jido.Integration.Registry.register(Jido.Integration.Examples.HelloWorld)

      # Execute
      envelope = Jido.Integration.Operation.Envelope.new("ping", %{"message" => "hello"})
      {:ok, result} = Jido.Integration.execute(Jido.Integration.Examples.HelloWorld, envelope)
      result.result["echo"]  #=> "hello"

      # Conformance
      report = Jido.Integration.Conformance.run(Jido.Integration.Examples.HelloWorld, profile: :bronze)
      report.pass_fail  #=> :pass
  """

  @behaviour Jido.Integration.Adapter

  alias Jido.Integration.{Error, Manifest}

  @impl true
  def id, do: "example_ping"

  @impl true
  def manifest do
    Manifest.new!(%{
      "id" => "example_ping",
      "display_name" => "Example Ping",
      "vendor" => "Jido",
      "domain" => "protocol",
      "version" => "0.1.0",
      "quality_tier" => "bronze",
      "telemetry_namespace" => "jido.integration.example_ping",
      "auth" => [
        %{
          "id" => "none",
          "type" => "none",
          "display_name" => "No Auth",
          "secret_refs" => [],
          "scopes" => [],
          "rotation_policy" => %{"required" => false, "interval_days" => nil},
          "tenant_binding" => "tenant_only",
          "health_check" => %{"enabled" => false, "interval_s" => 0}
        }
      ],
      "operations" => [
        %{
          "id" => "ping",
          "summary" => "Echo input with connector metadata.",
          "input_schema" => %{
            "type" => "object",
            "required" => ["message"],
            "properties" => %{"message" => %{"type" => "string", "minLength" => 1}}
          },
          "output_schema" => %{
            "type" => "object",
            "required" => ["echo", "connector_id"],
            "properties" => %{
              "echo" => %{"type" => "string"},
              "connector_id" => %{"type" => "string"}
            }
          },
          "errors" => [],
          "idempotency" => "optional",
          "timeout_ms" => 1_000,
          "rate_limit" => "gateway_default",
          "required_scopes" => []
        }
      ],
      "capabilities" => %{"custom.protocol.ping" => "native"}
    })
  end

  @impl true
  def validate_config(config) when is_map(config), do: {:ok, config}
  def validate_config(_), do: {:error, Error.new(:invalid_request, "config must be a map")}

  @impl true
  def health(_opts), do: {:ok, %{status: :healthy}}

  @impl true
  def run("ping", %{"message" => message}, opts) when is_binary(message) do
    tenant_id = Keyword.get(opts, :tenant_id, "unknown")

    :telemetry.execute(
      [:jido, :integration, :operation, :started],
      %{},
      %{connector_id: id(), operation_id: "ping"}
    )

    result = %{
      "echo" => message,
      "connector_id" => id(),
      "tenant_id" => tenant_id
    }

    :telemetry.execute(
      [:jido, :integration, :operation, :succeeded],
      %{},
      %{connector_id: id(), operation_id: "ping"}
    )

    {:ok, result}
  end

  def run(operation_id, _args, _opts) do
    {:error, Error.new(:unsupported, "Unsupported operation: #{operation_id}")}
  end
end
