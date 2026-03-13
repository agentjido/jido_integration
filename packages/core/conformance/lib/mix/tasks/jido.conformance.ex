defmodule Mix.Tasks.Jido.Conformance do
  @moduledoc """
  Run conformance checks against a connector and produce a report.

  ## Usage

      mix jido.conformance MyApp.Connectors.GitHub --profile bronze
      mix jido.conformance MyApp.Connectors.GitHub --profile bronze --output conformance_report.json

  ## Options

  - `--profile` — conformance profile: `mvp_foundation`, `bronze`, `silver`, `gold` (default: `bronze`)
  - `--output` — path to write JSON report (default: stdout summary only)
  - `--json` — output full JSON report to stdout instead of summary
  - `--format` — `summary` or `json` (default: `summary`)
  """

  use Mix.Task

  alias Jido.Integration.Conformance

  @shortdoc "Run conformance checks against a connector adapter"

  @profile_map %{
    "mvp_foundation" => :mvp_foundation,
    "bronze" => :bronze,
    "silver" => :silver,
    "gold" => :gold
  }
  @valid_formats ~w(summary json)

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [profile: :string, output: :string, json: :boolean, format: :string],
        aliases: [p: :profile, o: :output]
      )

    adapter_module = resolve_adapter(positional)
    config = load_conformance_config()
    profile = resolve_profile(opts, config)

    conformance_opts =
      [profile: profile]
      |> maybe_put_roles(config)
      |> maybe_put_fixture_dir(config)

    report = Conformance.run(adapter_module, conformance_opts)

    json_report = encode_report(report)

    if output_path = Keyword.get(opts, :output) do
      File.write!(output_path, json_report)
      Mix.shell().info("Conformance report written to #{output_path}")
    end

    if output_json?(opts) do
      Mix.shell().info(json_report)
    else
      print_summary(report)
    end

    if report.pass_fail == :fail do
      Mix.raise("Conformance check failed for #{report.connector_id} (profile: #{profile})")
    end
  end

  defp resolve_adapter([]) do
    Mix.raise("""
    No adapter module specified.

    Usage: mix jido.conformance MyApp.Connectors.GitHub --profile bronze
    """)
  end

  defp resolve_adapter([module_string | _]) do
    module =
      module_string
      |> String.replace_leading("Elixir.", "")
      |> then(&("Elixir." <> &1))
      |> safe_module_from_string(module_string)

    unless Code.ensure_loaded?(module) do
      Mix.raise("Module #{module_string} could not be loaded")
    end

    unless function_exported?(module, :manifest, 0) do
      Mix.raise(
        "Module #{module_string} does not implement the Adapter behaviour (missing manifest/0)"
      )
    end

    module
  end

  defp resolve_profile(opts, config) do
    profile_string =
      case Keyword.fetch(opts, :profile) do
        {:ok, profile} -> profile
        :error -> config_profile(config) || "bronze"
      end

    profile_string = to_string(profile_string)

    case Map.fetch(@profile_map, profile_string) do
      {:ok, profile} ->
        profile

      :error ->
        Mix.raise(
          "Invalid profile: #{profile_string}. Must be one of: #{Enum.join(Map.keys(@profile_map), ", ")}"
        )
    end
  end

  defp output_json?(opts) do
    format = Keyword.get(opts, :format, if(Keyword.get(opts, :json), do: "json", else: "summary"))

    unless format in @valid_formats do
      Mix.raise("Invalid format: #{format}. Must be one of: #{Enum.join(@valid_formats, ", ")}")
    end

    format == "json"
  end

  defp encode_report(report) do
    report
    |> stringify_report()
    |> Jason.encode!(pretty: true)
  end

  defp stringify_report(report) do
    %{
      "connector_id" => report.connector_id,
      "connector_version" => report.connector_version,
      "profile" => to_string(report.profile),
      "runner_version" => report.runner_version,
      "pass_fail" => to_string(report.pass_fail),
      "quality_tier_eligible" => report.quality_tier_eligible,
      "evidence_refs" => report.evidence_refs,
      "exceptions_applied" => report.exceptions_applied,
      "timestamp" => report.timestamp,
      "duration_ms" => report.duration_ms,
      "suite_results" =>
        Enum.map(report.suite_results, fn suite ->
          %{
            "suite" => suite.suite,
            "status" => to_string(suite.status),
            "duration_ms" => suite.duration_ms,
            "reason" => suite.reason,
            "checks" =>
              Enum.map(suite.checks, fn check ->
                %{
                  "name" => check.name,
                  "status" => to_string(check.status),
                  "message" => check.message
                }
              end)
          }
        end)
    }
  end

  defp print_summary(report) do
    status_icon = if report.pass_fail == :pass, do: "PASS", else: "FAIL"

    Mix.shell().info("")
    Mix.shell().info("=== Conformance Report: #{report.connector_id} ===")
    Mix.shell().info("Profile: #{report.profile}")
    Mix.shell().info("Result:  #{status_icon}")

    if report.quality_tier_eligible do
      Mix.shell().info("Tier:    #{report.quality_tier_eligible}")
    end

    Mix.shell().info("")

    Enum.each(report.suite_results, fn suite ->
      {icon, suffix} =
        case suite.status do
          :passed -> {"  [ok]", ""}
          :failed -> {"  [FAIL]", ""}
          :skipped -> {"  [SKIP]", " #{suite.reason}"}
        end

      Mix.shell().info("#{icon} #{suite.suite} (#{suite.duration_ms}ms)#{suffix}")
      print_failed_checks(suite.checks)
    end)

    Mix.shell().info("")
    Mix.shell().info("Duration: #{report.duration_ms}ms")
    Mix.shell().info("")
  end

  defp print_failed_checks(checks) do
    checks
    |> Enum.filter(&(&1.status == :failed))
    |> Enum.each(fn check ->
      msg = if check.message, do: " — #{check.message}", else: ""
      Mix.shell().info("        x #{check.name}#{msg}")
    end)
  end

  defp safe_module_from_string(module_name, original) do
    String.to_existing_atom(module_name)
  rescue
    ArgumentError -> Mix.raise("Module #{original} could not be loaded")
  end

  defp load_conformance_config do
    if File.exists?("conformance.exs") do
      case Code.eval_file("conformance.exs") do
        {config, _binding} when is_map(config) ->
          config

        {config, _binding} when is_list(config) ->
          Map.new(config)

        {_other, _binding} ->
          Mix.raise("conformance.exs must evaluate to a map or keyword list")
      end
    else
      %{}
    end
  end

  defp config_profile(config) do
    Map.get(config, :profile) || Map.get(config, "profile")
  end

  defp maybe_put_roles(opts, config) do
    case Map.get(config, :roles) || Map.get(config, "roles") do
      roles when is_list(roles) -> Keyword.put(opts, :roles, roles)
      _ -> opts
    end
  end

  defp maybe_put_fixture_dir(opts, config) do
    fixture_dir =
      Map.get(config, :fixture_dir) || Map.get(config, "fixture_dir") ||
        Map.get(config, :fixtures_dir) || Map.get(config, "fixtures_dir")

    case fixture_dir do
      path when is_binary(path) -> Keyword.put(opts, :fixture_dir, Path.expand(path))
      _ -> opts
    end
  end
end
