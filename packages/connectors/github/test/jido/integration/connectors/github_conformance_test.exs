defmodule Jido.Integration.Connectors.GitHubConformanceTest do
  use ExUnit.Case

  alias Jido.Integration.{Conformance, Error}
  alias Jido.Integration.Connectors.GitHub

  defmodule WebhookVerificationAdapter do
    @behaviour Jido.Integration.Adapter

    alias Jido.Integration.Manifest

    def id, do: "webhook_verifier"

    def manifest do
      Manifest.new!(%{
        "id" => "webhook_verifier",
        "display_name" => "Webhook Verifier",
        "vendor" => "Jido Test",
        "domain" => "protocol",
        "version" => "0.1.0",
        "quality_tier" => "bronze",
        "telemetry_namespace" => "jido.integration.webhook_verifier",
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
            "id" => "test.ping",
            "summary" => "Test ping operation",
            "input_schema" => %{"type" => "object"},
            "output_schema" => %{"type" => "object"},
            "errors" => [],
            "idempotency" => "optional",
            "timeout_ms" => 5_000,
            "rate_limit" => "gateway_default",
            "required_scopes" => []
          }
        ]
      })
    end

    def validate_config(config), do: {:ok, config}
    def health(_opts), do: {:ok, %{status: :healthy}}
    def run("test.ping", _args, _opts), do: {:ok, %{"pong" => true}}
    def run(_op, _args, _opts), do: {:error, Error.new(:unsupported, "nope")}
    def verify_webhook(_body, _signature, _secret), do: :ok
  end

  @moduletag :conformance

  test "GitHub connector passes mvp_foundation profile from the package" do
    beam_path = GitHub |> :code.which() |> List.to_string()
    assert beam_path =~ "/packages/connectors/github/"

    report = Conformance.run(GitHub, profile: :mvp_foundation)
    assert report.pass_fail == :pass
    assert report.connector_id == "github"
  end

  test "GitHub connector passes bronze profile from the package" do
    report = Conformance.run(GitHub, profile: :bronze)
    assert report.pass_fail == :pass
  end

  test "GitHub connector passes silver profile from the package" do
    report = Conformance.run(GitHub, profile: :silver)
    assert report.pass_fail == :pass
    assert suite(report, "triggers").status == :passed
    assert suite(report, "determinism").status == :skipped
    assert suite(report, "determinism").reason == "not_applicable: no_fixtures"
  end

  test "security hygiene still rejects connector-level webhook verification" do
    report = Conformance.run(WebhookVerificationAdapter, profile: :mvp_foundation)

    assert report.pass_fail == :fail

    assert Enum.any?(Conformance.failures(report), fn failure ->
             failure.name == "security.webhook_verification_control_plane_only"
           end)
  end

  defp suite(report, suite_name) do
    Enum.find(report.suite_results, &(&1.suite == suite_name))
  end
end
