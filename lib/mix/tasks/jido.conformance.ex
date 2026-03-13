defmodule Mix.Tasks.Jido.Conformance do
  use Mix.Task

  @moduledoc """
  Run v2-native connector conformance from the repo root.

  The reusable engine lives in `core/conformance`. This task stays in the root
  so the human-facing command surface remains stable while runtime logic
  remains package-owned.

  ## Usage

      mix jido.conformance Jido.Integration.V2.Connectors.GitHub
      mix jido.conformance Jido.Integration.V2.Connectors.GitHub --format json
      mix jido.conformance Jido.Integration.V2.Connectors.GitHub --output report.json
  """

  alias Jido.Integration.V2.Conformance
  alias Jido.Integration.V2.Conformance.Renderer
  alias Jido.Integration.V2.Conformance.Report
  alias Jido.Integration.Workspace.Monorepo

  @shortdoc "Run v2-native connector conformance from the repo root"

  @default_profile "connector_foundation"
  @formats ~w[human json]
  @format_atoms %{"human" => :human, "json" => :json}
  @profile_atoms %{@default_profile => :connector_foundation}
  @profile_names [@default_profile]
  @loader_project :jido_conformance_loader

  @impl Mix.Task
  def run(args) do
    {opts, positional, invalid} =
      OptionParser.parse(args,
        strict: [profile: :string, format: :string, output: :string],
        aliases: [p: :profile, o: :output]
      )

    validate_invalid_options!(invalid)

    module_string = resolve_module_name!(positional)
    profile = resolve_profile!(Keyword.get(opts, :profile, @default_profile))
    format = resolve_format!(Keyword.get(opts, :format, "human"))

    report = run_conformance!(module_string, profile)
    json_output = Renderer.render(report, :json)

    if output_path = Keyword.get(opts, :output) do
      File.write!(output_path, json_output)
      Mix.shell().info("Conformance report written to #{output_path}")
    end

    Mix.shell().info(Renderer.render(report, format))

    unless Report.passed?(report) do
      Mix.raise("Conformance failed for #{module_string}")
    end
  end

  defp validate_invalid_options!([]), do: :ok

  defp validate_invalid_options!(invalid) do
    formatted =
      Enum.map_join(invalid, ", ", fn
        {option, nil} when is_atom(option) -> Atom.to_string(option)
        {option, nil} -> to_string(option)
        {option, value} -> "#{option}=#{value}"
      end)

    Mix.raise("Invalid options: #{formatted}")
  end

  defp resolve_module_name!([module_string]), do: module_string

  defp resolve_module_name!([]) do
    Mix.raise("""
    No connector module specified.

    Usage: mix jido.conformance MyApp.Connectors.Example
    """)
  end

  defp resolve_module_name!(modules) do
    Mix.raise("Expected exactly one connector module, got: #{Enum.join(modules, ", ")}")
  end

  defp resolve_profile!(profile_name) do
    if profile_name in @profile_names do
      Map.fetch!(@profile_atoms, profile_name)
    else
      Mix.raise(
        "Invalid profile: #{profile_name}. Must be one of: #{Enum.join(@profile_names, ", ")}"
      )
    end
  end

  defp resolve_format!(format) when format in @formats, do: Map.fetch!(@format_atoms, format)

  defp resolve_format!(format) do
    Mix.raise("Invalid format: #{format}. Must be one of: #{Enum.join(@formats, ", ")}")
  end

  defp run_conformance!(module_string, profile) do
    normalized_module_name = normalize_module_name(module_string)

    case loaded_connector_module(normalized_module_name) do
      {:ok, module} ->
        run_loaded_connector!(module, profile)

      :error ->
        project_path = resolve_project_path!(module_string)
        run_in_project!(project_path, module_string, normalized_module_name, profile)
    end
  end

  defp run_loaded_connector!(module, profile) do
    case Conformance.run(module, profile: profile) do
      {:ok, report} ->
        report

      {:error, {:unknown_profile, profile_name}} ->
        Mix.raise("Invalid profile: #{profile_name}")

      {:error, reason} ->
        Mix.raise("Conformance could not run: #{inspect(reason)}")
    end
  end

  defp run_in_project!(project_path, module_string, normalized_module_name, profile) do
    project_root = Path.expand(project_path, Monorepo.root_dir())
    build_path = project_build_path(project_root)

    compile_project!(project_root, build_path)

    with_project_build_path(build_path, fn ->
      Mix.Project.in_project(@loader_project, project_root, fn _project ->
        prepare_project!()
        run_project_connector!(normalized_module_name, module_string, project_path, profile)
      end)
    end)
  end

  defp run_project_connector!(normalized_module_name, module_string, project_path, profile) do
    case loaded_connector_module(normalized_module_name) do
      {:ok, module} ->
        run_loaded_connector!(module, profile)

      :error ->
        Mix.raise("Module #{module_string} could not be loaded from #{project_path}")
    end
  end

  defp prepare_project! do
    Enum.each(["deps.loadpaths", "loadpaths"], &Mix.Task.reenable/1)
    Mix.Task.run("deps.loadpaths")
    Mix.Task.run("loadpaths")
  end

  defp compile_project!(project_root, build_path) do
    env = [{"MIX_ENV", Atom.to_string(Mix.env())}, {"MIX_BUILD_PATH", build_path}]

    case System.cmd("mix", ["compile", "--quiet"],
           cd: project_root,
           env: env,
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {output, exit_code} ->
        Mix.raise("""
        Could not compile #{project_root} for conformance.

        mix compile --quiet exited with #{exit_code}

        #{output}
        """)
    end
  end

  defp with_project_build_path(build_path, fun) do
    previous = System.get_env("MIX_BUILD_PATH")
    System.put_env("MIX_BUILD_PATH", build_path)

    try do
      fun.()
    after
      restore_env("MIX_BUILD_PATH", previous)
    end
  end

  defp project_build_path(project_root) do
    Path.join(project_root, "_build/#{Mix.env()}")
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp loaded_connector_module(normalized_module_name) do
    module = Module.concat([normalized_module_name])

    with true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :manifest, 0) do
      {:ok, module}
    else
      _ -> :error
    end
  end

  defp resolve_project_path!(module_string) do
    declaration = "defmodule " <> normalize_module_name(module_string)

    case Enum.find(Monorepo.package_paths(), &project_defines_module?(&1, declaration)) do
      nil ->
        Mix.raise("Module #{module_string} could not be resolved to a child package")

      project_path ->
        project_path
    end
  end

  defp project_defines_module?(project_path, declaration) do
    root = Monorepo.root_dir()
    pattern = Path.join(root, project_path <> "/lib/**/*.ex")

    pattern
    |> Path.wildcard()
    |> Enum.any?(fn path ->
      path
      |> File.read!()
      |> String.contains?(declaration)
    end)
  end

  defp normalize_module_name(module_string) do
    String.trim_leading(module_string, "Elixir.")
  end
end
