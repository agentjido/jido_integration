defmodule Jido.Integration.ConformanceTest do
  use ExUnit.Case
  @moduletag :conformance

  alias Jido.Integration.{Conformance, Error, Manifest}
  alias Jido.Integration.Test.{InvalidErrorAdapter, TestAdapter}

  defmodule WebhookVerificationAdapter do
    @behaviour Jido.Integration.Adapter

    alias Jido.Integration.Test.TestAdapter

    def id, do: "webhook_verifier"
    def manifest, do: TestAdapter.manifest()
    def validate_config(config), do: {:ok, config}
    def health(_opts), do: {:ok, %{status: :healthy}}
    def run("test.ping", _args, _opts), do: {:ok, %{"pong" => true}}
    def run(_op, _args, _opts), do: {:error, Error.new(:unsupported, "nope")}
    def verify_webhook(_body, _signature, _secret), do: :ok
  end

  defmodule LegacyTelemetryAdapter do
    @behaviour Jido.Integration.Adapter

    def id, do: "legacy_telemetry"

    def manifest do
      TestAdapter.manifest()
      |> Manifest.to_map()
      |> Map.put("id", "legacy_telemetry")
      |> Map.put("extensions", %{
        "telemetry_events" => ["jido.integration.dispatch_stub.accepted"]
      })
      |> Manifest.new!()
    end

    def validate_config(config), do: {:ok, config}
    def health(_opts), do: {:ok, %{status: :healthy}}
    def run("test.ping", _args, _opts), do: {:ok, %{"pong" => true}}
    def run(_op, _args, _opts), do: {:error, Error.new(:unsupported, "nope")}
  end

  describe "profiles/0" do
    test "returns valid profiles" do
      assert Conformance.profiles() == [:mvp_foundation, :bronze, :silver, :gold]
    end
  end

  describe "run/2 with TestAdapter" do
    test "passes mvp_foundation profile" do
      report = Conformance.run(TestAdapter, profile: :mvp_foundation)

      assert report.pass_fail == :pass
      assert report.connector_id == "test_adapter"
      assert report.connector_version == "0.1.0"
      assert report.profile == :mvp_foundation
      assert report.runner_version == "0.1.0"
      assert report.quality_tier_eligible == "bronze"
      assert report.evidence_refs != []
      assert report.exceptions_applied == []
    end

    test "includes all charter suite groups with profile and role gating" do
      report = Conformance.run(TestAdapter, profile: :mvp_foundation)

      assert Enum.map(report.suite_results, & &1.suite) == [
               "manifest",
               "operations",
               "triggers",
               "auth",
               "security",
               "gateway",
               "determinism",
               "telemetry",
               "compliance_minimum",
               "distributed_correctness",
               "artifact_transport",
               "policy_enforcement"
             ]

      assert suite(report, "manifest").status == :passed
      assert suite(report, "security").status == :passed
      assert suite(report, "telemetry").status == :passed
      assert suite(report, "compliance_minimum").status == :passed

      assert suite(report, "operations").status == :skipped
      assert suite(report, "operations").reason == "not_in_profile: mvp_foundation"

      assert suite(report, "distributed_correctness").status == :skipped
      assert suite(report, "distributed_correctness").reason == "not_applicable: role_mismatch"
      assert suite(report, "artifact_transport").status == :skipped
      assert suite(report, "policy_enforcement").status == :skipped
    end

    test "passes bronze profile" do
      report = Conformance.run(TestAdapter, profile: :bronze)
      assert report.pass_fail == :pass
      assert suite(report, "operations").status == :passed
      assert suite(report, "auth").status == :passed
      assert suite(report, "gateway").status == :passed
    end

    test "records duration" do
      report = Conformance.run(TestAdapter, profile: :mvp_foundation)
      assert is_integer(report.duration_ms)
      assert report.duration_ms >= 0
    end
  end

  describe "security hygiene" do
    test "fails adapters that implement connector-level webhook verification" do
      report = Conformance.run(WebhookVerificationAdapter, profile: :mvp_foundation)

      assert report.pass_fail == :fail

      assert Enum.any?(Conformance.failures(report), fn failure ->
               failure.name == "security.webhook_verification_control_plane_only"
             end)
    end
  end

  describe "telemetry contract" do
    test "fails adapters that advertise legacy dispatch_stub telemetry events" do
      report = Conformance.run(LegacyTelemetryAdapter, profile: :mvp_foundation)

      assert report.pass_fail == :fail

      assert Enum.any?(Conformance.failures(report), fn failure ->
               failure.name ==
                 "telemetry.event_valid.jido.integration.dispatch_stub.accepted"
             end)
    end
  end

  describe "passed?/1" do
    test "returns true for passing report" do
      report = Conformance.run(TestAdapter, profile: :mvp_foundation)
      assert Conformance.passed?(report)
    end
  end

  describe "failures/1" do
    test "returns empty list for passing report" do
      report = Conformance.run(TestAdapter, profile: :mvp_foundation)
      assert Conformance.failures(report) == []
    end
  end

  describe "run/2 with malformed connector metadata" do
    test "reports invalid error declarations instead of crashing" do
      report = Conformance.run(InvalidErrorAdapter, profile: :mvp_foundation)

      assert report.pass_fail == :fail

      assert Enum.any?(Conformance.failures(report), fn failure ->
               failure.name =~ "invalid_error.run"
             end)
    end
  end

  defp suite(report, suite_name) do
    Enum.find(report.suite_results, &(&1.suite == suite_name))
  end
end
