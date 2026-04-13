defmodule Mix.Tasks.Jido.Conformance do
  use Mix.Task

  @moduledoc """
  Run v2-native connector conformance from the repo root.

  This task is the stable root connector acceptance contract for package-level
  conformance. Package-local fixtures stay package-local, but the review
  command runs from the workspace root so every connector is judged through one
  repo-owned surface.

  Use it after package-local verification and before the root `mix ci`
  acceptance gate. The reusable engine lives in `core/conformance`; the root
  task exists so the human-facing contract stays stable while runtime logic
  remains package-owned.

  ## Usage

      mix jido.conformance Jido.Integration.V2.Connectors.GitHub
      mix jido.conformance Jido.Integration.V2.Connectors.GitHub --format json
      mix jido.conformance Jido.Integration.V2.Connectors.GitHub --output report.json
  """

  alias Jido.Integration.Toolchain
  alias Jido.Integration.V2.Conformance
  alias Jido.Integration.V2.Conformance.Renderer
  alias Jido.Integration.V2.Conformance.Report

  @shortdoc "Run v2-native connector conformance from the repo root"

  @default_profile "connector_foundation"
  @formats ~w[human json]
  @format_atoms %{"human" => :human, "json" => :json}
  @profile_atoms %{@default_profile => :connector_foundation}
  @profile_names [@default_profile]
  @loader_project :jido_conformance_loader
  @active_project_globs [".", "core/*", "connectors/*", "apps/*"]

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

    case resolve_project_path(module_string) do
      {:ok, project_path} ->
        run_in_project!(project_path, module_string, normalized_module_name, profile)

      :error ->
        case loaded_connector_module(normalized_module_name) do
          {:ok, module} ->
            run_loaded_connector!(module, profile)

          :error ->
            Mix.raise("Module #{module_string} could not be resolved to a child package")
        end
    end
  end

  defp run_loaded_connector!(module, profile) do
    ensure_runtime_apps_started!()

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
    project_root = Path.expand(project_path, repo_root())
    runtime_root = conformance_runtime_root(project_root)
    build_path = project_build_path(runtime_root)
    hex_home = project_hex_home(runtime_root)

    File.mkdir_p!(build_path)
    File.mkdir_p!(hex_home)

    deps_get_project!(project_root, build_path, hex_home)
    compile_project!(project_root, build_path, hex_home)
    hydrate_dependency_priv!(project_root, build_path)

    with_project_build_path(build_path, fn ->
      with_restored_code_path(fn ->
        load_project_connector!(
          project_root,
          build_path,
          normalized_module_name,
          module_string,
          project_path,
          profile
        )
      end)
    end)
  end

  defp load_project_connector!(
         project_root,
         build_path,
         normalized_module_name,
         module_string,
         project_path,
         profile
       ) do
    Mix.Project.in_project(@loader_project, project_root, fn _project ->
      prepare_project!()
      prepend_build_loadpaths!(build_path)
      run_project_connector!(normalized_module_name, module_string, project_path, profile)
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

  defp prepend_build_loadpaths!(build_path) do
    build_path
    |> Path.join("lib/*/ebin")
    |> Path.wildcard()
    |> Enum.map(&String.to_charlist/1)
    |> Code.prepend_paths()

    :ok
  end

  defp deps_get_project!(project_root, build_path, hex_home, opts \\ []) do
    if Keyword.get(opts, :force, false) or not File.dir?(Path.join(project_root, "deps")) do
      env = project_command_env(project_root, build_path, hex_home)

      case System.cmd(mix_executable(), ["deps.get"],
             cd: project_root,
             env: env,
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          :ok

        {output, exit_code} ->
          Mix.raise("""
          Could not fetch dependencies for #{project_root} during conformance.

          mix deps.get exited with #{exit_code}

          #{output}
          """)
      end
    else
      :ok
    end
  end

  defp compile_project!(project_root, build_path, hex_home) do
    env = project_command_env(project_root, build_path, hex_home)

    case System.cmd(mix_executable(), ["compile", "--quiet"],
           cd: project_root,
           env: env,
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {output, exit_code} ->
        maybe_retry_compile_project!(project_root, build_path, hex_home, output, exit_code)
    end
  end

  defp maybe_retry_compile_project!(project_root, build_path, hex_home, output, exit_code) do
    if stale_dependency_output?(output) do
      deps_get_project!(project_root, build_path, hex_home, force: true)

      case System.cmd(mix_executable(), ["compile", "--quiet"],
             cd: project_root,
             env: project_command_env(project_root, build_path, hex_home),
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          :ok

        {retry_output, retry_exit_code} ->
          raise_compile_project_error!(project_root, retry_output, retry_exit_code)
      end
    else
      raise_compile_project_error!(project_root, output, exit_code)
    end
  end

  defp stale_dependency_output?(output) when is_binary(output) do
    String.contains?(output, "Unchecked dependencies") and
      Enum.any?(
        [
          "dependency does not match the requirement",
          "the dependency is not locked",
          "different specs were given for the"
        ],
        &String.contains?(output, &1)
      )
  end

  @spec raise_compile_project_error!(String.t(), String.t(), integer()) :: no_return()
  defp raise_compile_project_error!(project_root, output, exit_code) do
    Mix.raise("""
    Could not compile #{project_root} for conformance.

    mix compile --quiet exited with #{exit_code}

    #{output}
    """)
  end

  defp hydrate_dependency_priv!(project_root, build_path) do
    deps_root = Path.join(project_root, "deps")
    build_lib_root = Path.join(build_path, "lib")

    if File.dir?(deps_root) and File.dir?(build_lib_root) do
      deps_root
      |> Path.join("*")
      |> Path.wildcard()
      |> Enum.each(&copy_dependency_priv!(&1, build_lib_root))
    end

    :ok
  end

  defp copy_dependency_priv!(dep_root, build_lib_root) do
    app_name = Path.basename(dep_root)
    source_priv = Path.join(dep_root, "priv")
    target_priv = Path.join([build_lib_root, app_name, "priv"])

    cond do
      not File.dir?(source_priv) ->
        :ok

      File.dir?(target_priv) ->
        :ok

      true ->
        File.mkdir_p!(Path.dirname(target_priv))
        File.cp_r!(source_priv, target_priv)
        :ok
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

  defp with_restored_code_path(fun) do
    previous = :code.get_path()

    try do
      fun.()
    after
      :code.set_path(previous)
    end
  end

  defp project_build_path(runtime_root) do
    Path.join(runtime_root, "build")
  end

  defp project_hex_home(runtime_root) do
    Path.join(runtime_root, "hex")
  end

  defp conformance_runtime_root(project_root) do
    Path.join([
      repo_root(),
      "_build",
      "jido_conformance",
      Atom.to_string(Mix.env()),
      stable_project_slug(project_root)
    ])
  end

  defp stable_project_slug(project_root) do
    digest =
      :crypto.hash(:sha256, project_cache_fingerprint(project_root))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    project_name =
      project_root
      |> Path.relative_to(repo_root())
      |> String.replace(~r/[^a-zA-Z0-9]+/, "_")
      |> String.trim("_")

    "#{project_name}_#{digest}"
  end

  defp project_cache_fingerprint(project_root) do
    [
      project_root,
      project_file_fingerprint(project_root, "mix.exs"),
      project_file_fingerprint(project_root, "mix.lock")
    ]
    |> Enum.join("\n")
  end

  defp project_file_fingerprint(project_root, relative_path) do
    path = Path.join(project_root, relative_path)

    case File.read(path) do
      {:ok, contents} ->
        contents

      {:error, :enoent} ->
        ""

      {:error, reason} ->
        Mix.raise("Could not read #{path} for conformance cache key: #{inspect(reason)}")
    end
  end

  defp project_command_env(project_root, build_path, hex_home) do
    [
      {"MIX_ENV", Atom.to_string(Mix.env())},
      {"MIX_BUILD_PATH", build_path},
      {"MIX_DEPS_PATH", Path.join(project_root, "deps")},
      {"MIX_LOCKFILE", Path.join(project_root, "mix.lock")},
      {"HEX_HOME", hex_home},
      {"HEX_API_KEY", nil}
    ]
  end

  defp mix_executable do
    Toolchain.mix_executable()
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

  defp resolve_project_path(module_string) do
    declaration = "defmodule " <> normalize_module_name(module_string)

    case Enum.find(active_project_paths(), &project_defines_module?(&1, declaration)) do
      nil -> :error
      project_path -> {:ok, project_path}
    end
  end

  defp project_defines_module?(project_path, declaration) do
    root = repo_root()
    pattern = Path.join(root, project_path <> "/lib/**/*.ex")

    pattern
    |> Path.wildcard()
    |> Enum.any?(fn path ->
      path
      |> File.read!()
      |> String.contains?(declaration)
    end)
  end

  defp active_project_paths do
    root = repo_root()

    @active_project_globs
    |> Enum.flat_map(fn
      "." ->
        ["."]

      glob ->
        root
        |> Path.join(glob)
        |> Path.wildcard()
        |> Enum.filter(&File.dir?/1)
        |> Enum.map(&Path.relative_to(&1, root))
    end)
  end

  defp repo_root do
    Path.expand("../../..", __DIR__)
  end

  defp normalize_module_name(module_string) do
    String.trim_leading(module_string, "Elixir.")
  end

  defp ensure_runtime_apps_started! do
    case Application.ensure_all_started(:telemetry) do
      {:ok, _apps} ->
        :ok

      {:error, {:telemetry, reason}} ->
        Mix.raise("Could not start :telemetry for conformance: #{inspect(reason)}")

      {:error, {app, reason}} ->
        Mix.raise("Could not start #{inspect(app)} for conformance: #{inspect(reason)}")
    end
  end
end
