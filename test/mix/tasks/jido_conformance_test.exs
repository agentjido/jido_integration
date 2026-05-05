defmodule Mix.Tasks.Jido.ConformanceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Jido.Integration.TestTmpDir
  alias Jido.Integration.V2.RuntimeRouter
  alias Mix.Tasks.Jido.Conformance, as: ConformanceTask

  @tag timeout: 180_000
  test "prints a human-readable conformance report by default" do
    output = run_task(["Jido.Integration.V2.Connectors.GitHub"])

    assert output =~ "Connector: github"
    assert output =~ "Profile: connector_foundation"
    assert output =~ "[PASS] manifest_contract"
    assert output =~ "[SKIP] ingress_definition_discipline"
  end

  @tag timeout: 180_000
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

  @tag timeout: 180_000
  test "loads connector packages that depend on package-local external deps" do
    output = run_task(["Jido.Integration.V2.Connectors.Notion"])

    assert output =~ "Connector: notion"
    assert output =~ "[PASS] deterministic_fixtures"
  end

  @tag timeout: 180_000
  test "loads the Linear connector package through the root conformance task" do
    output = run_task(["Jido.Integration.V2.Connectors.Linear"])

    assert output =~ "Connector: linear"
    assert output =~ "[PASS] deterministic_fixtures"
  end

  @tag timeout: 180_000
  test "boots the runtime router explicitly for non-direct connector conformance" do
    stop_runtime_router!()

    output = run_task(["Jido.Integration.V2.Connectors.CodexCli"])

    assert output =~ "Connector: codex_cli"
    assert output =~ "[PASS] deterministic_fixtures"
  end

  @tag timeout: 180_000
  test "restores the original code path after loading a child package" do
    original_path = :code.get_path()

    run_task(["Jido.Integration.V2.Connectors.Notion"])

    assert :code.get_path() == original_path
  end

  test "raises on an invalid connector module" do
    assert_raise Mix.Error, fn ->
      run_task(["Does.Not.Exist"])
    end
  end

  test "rejects unknown connector module names without creating module atoms" do
    unknown_module =
      "Jido.Integration.V2.Connectors.UnknownAtomLeak#{System.unique_integer([:positive])}"

    refute existing_atom?(unknown_module)

    assert_raise Mix.Error, fn ->
      run_task([unknown_module])
    end

    refute existing_atom?(unknown_module)
  end

  test "raises on an invalid profile" do
    assert_raise Mix.Error, fn ->
      run_task(["Jido.Integration.V2.Connectors.GitHub", "--profile", "async"])
    end
  end

  defp run_task(args) do
    with_progress("jido.conformance #{Enum.join(args, " ")}", fn ->
      Mix.Task.reenable("jido.conformance")

      capture_io(fn ->
        ConformanceTask.run(args)
      end)
    end)
  end

  defp temp_dir!(label) do
    path = TestTmpDir.create!("jido_integration_#{label}")

    on_exit(fn -> TestTmpDir.cleanup!(path) end)
    path
  end

  defp with_progress(label, fun) when is_function(fun, 0) do
    started_at = System.monotonic_time(:millisecond)
    IO.puts(:stderr, "[progress] starting #{label}")

    try do
      fun.()
    after
      finished_at = System.monotonic_time(:millisecond)
      IO.puts(:stderr, "[progress] finished #{label} in #{finished_at - started_at}ms")
    end
  end

  defp stop_runtime_router! do
    RuntimeRouter.stop!()
  end

  defp existing_atom?(module_name) do
    _module = String.to_existing_atom("Elixir." <> module_name)
    true
  rescue
    ArgumentError -> false
  end
end
