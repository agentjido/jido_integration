defmodule Jido.Integration.Test.ScopedTestAdapter do
  @moduledoc false
  @behaviour Jido.Integration.Adapter

  alias Jido.Integration.{Error, Manifest}

  @impl true
  def id, do: "scoped_test"

  @impl true
  def manifest do
    Manifest.new!(%{
      "id" => "scoped_test",
      "display_name" => "Scoped Test Adapter",
      "vendor" => "Test",
      "domain" => "saas",
      "version" => "0.1.0",
      "quality_tier" => "bronze",
      "telemetry_namespace" => "jido.integration.scoped_test",
      "auth" => [
        %{
          "id" => "oauth2",
          "type" => "oauth2",
          "display_name" => "OAuth2",
          "secret_refs" => [],
          "scopes" => ["repo", "read:org"],
          "rotation_policy" => %{"required" => false, "interval_days" => nil},
          "tenant_binding" => "tenant_only",
          "health_check" => %{"enabled" => false, "interval_s" => 0}
        }
      ],
      "operations" => [
        %{
          "id" => "scoped_op",
          "summary" => "An operation requiring repo scope",
          "input_schema" => %{
            "type" => "object",
            "required" => ["data"],
            "properties" => %{"data" => %{"type" => "string"}}
          },
          "output_schema" => %{
            "type" => "object",
            "properties" => %{
              "result" => %{"type" => "string"},
              "token_used" => %{"type" => "string"}
            }
          },
          "errors" => [],
          "idempotency" => "none",
          "timeout_ms" => 5_000,
          "rate_limit" => "gateway_default",
          "required_scopes" => ["repo"]
        },
        %{
          "id" => "unscoped_op",
          "summary" => "An operation requiring no scopes",
          "input_schema" => %{
            "type" => "object",
            "required" => ["data"],
            "properties" => %{"data" => %{"type" => "string"}}
          },
          "output_schema" => %{
            "type" => "object",
            "properties" => %{
              "result" => %{"type" => "string"}
            }
          },
          "errors" => [],
          "idempotency" => "none",
          "timeout_ms" => 5_000,
          "rate_limit" => "gateway_default",
          "required_scopes" => []
        }
      ],
      "capabilities" => %{}
    })
  end

  @impl true
  def validate_config(config), do: {:ok, config}

  @impl true
  def health(_opts), do: {:ok, %{status: :healthy}}

  @impl true
  def run("scoped_op", %{"data" => data}, opts) do
    token = Keyword.get(opts, :token, "no_token")
    {:ok, %{"result" => data, "token_used" => token}}
  end

  def run("unscoped_op", %{"data" => data}, _opts) do
    {:ok, %{"result" => data}}
  end

  def run(op, _args, _opts) do
    {:error, Error.new(:unsupported, "Unknown: #{op}")}
  end
end
