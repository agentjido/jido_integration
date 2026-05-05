defmodule Jido.Integration.V2.Conformance do
  @moduledoc """
  V2-native connector conformance engine.

  The engine evaluates stable suite ids selected by a named profile. That keeps
  the root `mix jido.conformance` task API stable while allowing future
  profiles to add async or webhook-routing suites without changing invocation
  shape.
  """

  alias Jido.Integration.V2.Conformance.CheckResult
  alias Jido.Integration.V2.Conformance.Profile
  alias Jido.Integration.V2.Conformance.Report
  alias Jido.Integration.V2.Conformance.SuiteResult
  alias Jido.Integration.V2.Conformance.Suites.CapabilityContracts
  alias Jido.Integration.V2.Conformance.Suites.ConsumerSurfaceProjection
  alias Jido.Integration.V2.Conformance.Suites.DeterministicFixtures
  alias Jido.Integration.V2.Conformance.Suites.IngressDefinitionDiscipline
  alias Jido.Integration.V2.Conformance.Suites.ManifestContract
  alias Jido.Integration.V2.Conformance.Suites.PolicyContract
  alias Jido.Integration.V2.Conformance.Suites.RuntimeClassFit
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.RuntimeRouter

  @suite_modules %{
    manifest_contract: ManifestContract,
    consumer_surface_projection: ConsumerSurfaceProjection,
    capability_contracts: CapabilityContracts,
    runtime_class_fit: RuntimeClassFit,
    policy_contract: PolicyContract,
    deterministic_fixtures: DeterministicFixtures,
    ingress_definition_discipline: IngressDefinitionDiscipline
  }

  @type run_option ::
          {:profile, Profile.name() | String.t()}
          | {:generated_at, DateTime.t()}
          | {:fixtures, list()}
          | {:runtime_drivers, map()}
          | {:ingress_definitions, list()}

  @spec profiles() :: [Profile.name()]
  def profiles, do: Profile.names()

  @spec run(module(), [run_option()]) :: {:ok, Report.t()} | {:error, term()}
  def run(connector_module, opts \\ []) when is_atom(connector_module) do
    with :ok <- validate_connector_module(connector_module),
         {:ok, profile} <- fetch_profile(Keyword.get(opts, :profile, Profile.default().name)),
         {:ok, manifest} <- fetch_manifest(connector_module) do
      runtime_drivers =
        Keyword.get(
          opts,
          :runtime_drivers,
          load_connector_export(connector_module, :runtime_drivers)
        )

      with_runtime_drivers(runtime_drivers, fn ->
        context =
          build_context(
            connector_module,
            manifest,
            Keyword.get(opts, :fixtures, load_connector_export(connector_module, :fixtures)),
            Keyword.get(
              opts,
              :ingress_definitions,
              load_connector_export(connector_module, :ingress_definitions)
            )
          )

        suite_results = Enum.map(profile.suite_ids, &run_suite(&1, context))

        {:ok,
         %Report{
           connector_module: connector_module,
           connector_id: manifest.connector,
           profile: profile.name,
           runner_version: runner_version(),
           generated_at:
             Keyword.get(opts, :generated_at, DateTime.utc_now() |> DateTime.truncate(:second)),
           status: report_status(suite_results),
           suite_results: suite_results
         }}
      end)
    end
  end

  defp validate_connector_module(module) do
    case Code.ensure_loaded(module) do
      {:module, _loaded_module} ->
        if function_exported?(module, :manifest, 0) do
          :ok
        else
          {:error, {:invalid_connector_module, inspect(module)}}
        end

      {:error, _reason} ->
        {:error, {:module_not_loaded, inspect(module)}}
    end
  end

  defp fetch_profile(profile_name) do
    case Profile.fetch(profile_name) do
      {:ok, profile} -> {:ok, profile}
      :error -> {:error, {:unknown_profile, profile_name}}
    end
  end

  defp fetch_manifest(connector_module) do
    manifest = connector_module.manifest()

    if struct_instance?(manifest, Manifest) do
      {:ok, manifest}
    else
      {:error, {:invalid_manifest, inspect(manifest)}}
    end
  rescue
    error ->
      {:error, {:manifest_error, Exception.message(error)}}
  end

  defp build_context(connector_module, manifest, fixtures, ingress_definitions) do
    %{
      connector_module: connector_module,
      manifest: manifest,
      fixtures: fixtures,
      ingress_definitions: ingress_definitions
    }
  end

  defp load_connector_export(connector_module, export_name) do
    companion_name = Atom.to_string(connector_module) <> ".Conformance"

    case available_module_named(companion_name) do
      {:ok, companion_module} ->
        if function_exported?(companion_module, export_name, 0) do
          apply(companion_module, export_name, [])
        else
          []
        end

      :error ->
        []
    end
  end

  defp available_module_named(module_name) do
    case loaded_module_named(module_name) do
      {:ok, module} -> {:ok, module}
      :error -> load_available_module_named(module_name)
    end
  end

  defp loaded_module_named(module_name) do
    Enum.find_value(:code.all_loaded(), :error, fn {module, _path} ->
      if Atom.to_string(module) == module_name do
        {:ok, module}
      end
    end)
  end

  defp load_available_module_named(module_name) do
    Enum.find_value(:code.all_available(), :error, fn {available_name, beam_path, _loaded?} ->
      if List.to_string(available_name) == module_name do
        load_beam_module(module_name, List.to_string(beam_path))
      end
    end)
  end

  defp load_beam_module(module_name, beam_path) do
    beam_path
    |> Path.rootname()
    |> String.to_charlist()
    |> :code.load_abs()
    |> case do
      {:module, module} ->
        if Atom.to_string(module) == module_name do
          {:ok, module}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp with_runtime_drivers(runtime_drivers, fun) when runtime_drivers in [%{}, []], do: fun.()

  defp with_runtime_drivers(runtime_drivers, fun) when is_map(runtime_drivers) do
    RuntimeRouter.start!()

    previous_runtime_drivers =
      Application.get_env(:jido_integration_v2_control_plane, :runtime_drivers)

    Application.put_env(:jido_integration_v2_control_plane, :runtime_drivers, runtime_drivers)
    RuntimeRouter.reset!()

    try do
      fun.()
    after
      case previous_runtime_drivers do
        nil ->
          Application.delete_env(:jido_integration_v2_control_plane, :runtime_drivers)

        value ->
          Application.put_env(:jido_integration_v2_control_plane, :runtime_drivers, value)
      end

      RuntimeRouter.reset!()
    end
  end

  defp run_suite(suite_id, context) do
    suite_module = Map.fetch!(@suite_modules, suite_id)
    suite_module.run(context)
  rescue
    error ->
      SuiteResult.from_checks(
        suite_id,
        [
          CheckResult.fail("#{suite_id}.exception", Exception.message(error))
        ],
        "suite execution raised"
      )
  end

  defp runner_version do
    case Application.spec(:jido_integration_v2_conformance, :vsn) do
      nil -> "0.1.0"
      version when is_list(version) -> List.to_string(version)
      version -> to_string(version)
    end
  end

  defp report_status(suite_results) do
    if Enum.any?(suite_results, &(&1.status == :failed)), do: :failed, else: :passed
  end

  defp struct_instance?(value, module),
    do: is_map(value) and Map.get(value, :__struct__) == module
end
