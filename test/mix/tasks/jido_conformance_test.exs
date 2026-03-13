defmodule Mix.Tasks.Jido.ConformanceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Jido.Conformance, as: ConformanceTask

  test "prints a human-readable conformance report by default" do
    output = run_task(["Jido.Integration.V2.Connectors.GitHub"])

    assert output =~ "Connector: github"
    assert output =~ "Profile: connector_foundation"
    assert output =~ "[PASS] manifest_contract"
    assert output =~ "[SKIP] ingress_definition_discipline"
  end

  test "prints JSON and writes the JSON report to a file" do
    output_dir = temp_dir!("json-output")
    output_path = Path.join(output_dir, "github_conformance.json")

    output =
      run_task([
        "Jido.Integration.V2.Connectors.GitHub",
        "--format",
        "json",
        "--output",
        output_path
      ])

    assert output =~ "\"connector_id\": \"github\""
    assert output =~ "\"profile\": \"connector_foundation\""
    assert File.read!(output_path) =~ "\"deterministic_fixtures\""
  end

  test "raises on an invalid connector module" do
    assert_raise Mix.Error, ~r/could not be resolved to a child package/, fn ->
      run_task(["Does.Not.Exist"])
    end
  end

  test "raises on an invalid profile" do
    assert_raise Mix.Error, ~r/Invalid profile/, fn ->
      run_task(["Jido.Integration.V2.Connectors.GitHub", "--profile", "async"])
    end
  end

  defp run_task(args) do
    Mix.Task.reenable("jido.conformance")

    capture_io(fn ->
      ConformanceTask.run(args)
    end)
  end

  defp temp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_integration_#{label}_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(path)
    path
  end
end
