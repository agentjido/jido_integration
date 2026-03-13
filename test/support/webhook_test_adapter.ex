defmodule Jido.Integration.Test.WebhookTestAdapter do
  @moduledoc false
  @behaviour Jido.Integration.Adapter

  alias Jido.Integration.{Error, Manifest}

  @impl true
  def id, do: "webhook_test"

  @impl true
  def manifest do
    Manifest.new!(%{
      "id" => id(),
      "display_name" => "Webhook Test Adapter",
      "vendor" => "Jido Test",
      "domain" => "protocol",
      "version" => "0.1.0",
      "quality_tier" => "bronze",
      "telemetry_namespace" => "jido.integration.webhook_test",
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
      "triggers" => [
        %{
          "id" => "webhook_test.webhook.event",
          "class" => "webhook",
          "summary" => "Generic webhook event",
          "payload_schema" => %{"type" => "object"},
          "delivery_semantics" => "at_least_once",
          "ordering_scope" => "tenant_connector",
          "checkpoint_mode" => "cursor",
          "dedupe_key_path" => "$.headers.x-delivery-id",
          "max_delivery_lag_s" => 300,
          "verification" => %{
            "type" => "hmac",
            "algorithm" => "sha256",
            "header" => "x-signature-256"
          },
          "callback_topology" => "dynamic_per_install",
          "replay_window_days" => 7,
          "backfill_supported" => false
        }
      ],
      "capabilities" => %{
        "triggers.webhook" => "native"
      }
    })
  end

  @impl true
  def validate_config(config), do: {:ok, config}

  @impl true
  def health(_opts), do: {:ok, %{status: :healthy}}

  @impl true
  def run(op, _args, _opts) do
    {:error, Error.new(:unsupported, "Unknown operation: #{op}")}
  end

  @impl true
  def handle_trigger("webhook_test.webhook.event", payload) do
    {:ok,
     %{
       "event_type" => get_in(payload, ["headers", "x-event-type"]) || "unknown",
       "delivery_id" => get_in(payload, ["headers", "x-delivery-id"]),
       "payload" => Map.get(payload, "body", %{})
     }}
  end

  def handle_trigger(trigger_id, _payload) do
    {:error, Error.new(:unsupported, "Unknown trigger: #{trigger_id}")}
  end
end
