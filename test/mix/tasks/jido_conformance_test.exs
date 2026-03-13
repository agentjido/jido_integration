defmodule Mix.Tasks.Jido.ConformanceTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Mix.Tasks.Jido.Conformance, as: ConformanceTask

  @moduletag :tmp_dir

  describe "mix jido.conformance" do
    test "writes the charter-aligned JSON report to a file", %{tmp_dir: tmp_dir} do
      output_path = Path.join(tmp_dir, "conformance_report.json")

      output =
        run_task([
          "Jido.Integration.Examples.HelloWorld",
          "--profile",
          "bronze",
          "--output",
          output_path,
          "--format",
          "json"
        ])

      assert output =~ "\"connector_id\": \"example_ping\""
      assert File.exists?(output_path)

      parsed = output_path |> File.read!() |> Jason.decode!()

      assert parsed["connector_id"] == "example_ping"
      assert parsed["profile"] == "bronze"
      assert parsed["runner_version"] == "0.1.0"
      assert parsed["pass_fail"] == "pass"
      assert parsed["quality_tier_eligible"] == "bronze"
      assert is_list(parsed["evidence_refs"])
      assert parsed["exceptions_applied"] == []
      assert length(parsed["suite_results"]) == 12

      assert Enum.any?(parsed["suite_results"], fn suite ->
               suite["suite"] == "distributed_correctness" and suite["status"] == "skipped" and
                 suite["reason"] == "not_applicable: role_mismatch"
             end)
    end

    test "--json emits the full report to stdout" do
      output =
        run_task([
          "Jido.Integration.Examples.HelloWorld",
          "--profile",
          "mvp_foundation",
          "--json"
        ])

      assert output =~ "\"connector_id\": \"example_ping\""
      assert output =~ "\"runner_version\": \"0.1.0\""
      assert output =~ "\"evidence_refs\""
    end

    test "raises on invalid module name" do
      assert_raise Mix.Error, ~r/could not be loaded/, fn ->
        run_task(["Does.Not.Exist", "--profile", "bronze"])
      end
    end

    test "raises on invalid profile" do
      assert_raise Mix.Error, ~r/Invalid profile/, fn ->
        run_task(["Jido.Integration.Examples.HelloWorld", "--profile", "platinum"])
      end
    end

    test "raises on invalid format" do
      assert_raise Mix.Error, ~r/Invalid format/, fn ->
        run_task([
          "Jido.Integration.Examples.HelloWorld",
          "--profile",
          "bronze",
          "--format",
          "yaml"
        ])
      end
    end

    test "loads role overrides from conformance.exs", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "conformance.exs"), "%{roles: [:dispatch_consumer]}")

      output =
        File.cd!(tmp_dir, fn ->
          run_task([
            "Jido.Integration.Examples.HelloWorld",
            "--profile",
            "mvp_foundation",
            "--format",
            "json"
          ])
        end)

      json = Jason.decode!(output)

      assert Enum.any?(json["suite_results"], fn suite ->
               suite["suite"] == "distributed_correctness" and suite["status"] == "passed"
             end)
    end
  end

  defp run_task(args) do
    Mix.Task.reenable("jido.conformance")

    capture_io(fn ->
      ConformanceTask.run(args)
    end)
  end
end
