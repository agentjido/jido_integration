defmodule Jido.Integration.Workspace.ConnectorScaffold do
  @moduledoc false

  import Mix.Generator

  alias Jido.Integration.Workspace.Monorepo

  @runtime_classes [:direct, :session, :stream]
  @default_runtime_class :direct

  @type runtime_class :: :direct | :session | :stream

  @spec generate!(String.t(), keyword()) :: map()
  def generate!(connector_name, opts \\ []) do
    context = build_context(connector_name, opts)
    ensure_package_root_available!(context)

    files = files(context)

    files
    |> Enum.map(fn {_template_name, relative_target_path} ->
      Path.dirname(Path.join(context.package_root, relative_target_path))
    end)
    |> Enum.uniq()
    |> Enum.each(&create_directory/1)

    Enum.each(files, fn
      {:workspace_lockfile, relative_target_path} ->
        File.cp!(
          context.workspace_lockfile_path,
          Path.join(context.package_root, relative_target_path)
        )

      {template_name, relative_target_path} ->
        copy_template(
          template_path(template_name),
          Path.join(context.package_root, relative_target_path),
          Map.to_list(context)
        )
    end)

    context
  end

  @spec generated_relative_paths(map()) :: [String.t()]
  def generated_relative_paths(context) do
    Enum.map(files(context), fn {_template_name, relative_target_path} ->
      Path.relative_to(
        Path.join(context.package_root, relative_target_path),
        context.workspace_root
      )
    end)
  end

  defp build_context(connector_name, opts) do
    connector_name = normalize_connector_name!(connector_name)
    workspace_root = opts |> Keyword.get(:workspace_root, Monorepo.root_dir()) |> Path.expand()

    runtime_class =
      resolve_runtime_class!(Keyword.get(opts, :runtime_class, @default_runtime_class))

    ensure_scaffoldable_runtime_class!(runtime_class, connector_name)

    connector_module =
      normalize_module_name(Keyword.get(opts, :module, default_module_name(connector_name)))

    package_root = resolve_package_root(workspace_root, connector_name, Keyword.get(opts, :path))
    project_name = resolve_project_name(connector_name, Keyword.get(opts, :package_name))
    project_module = connector_module <> ".MixProject"
    module_file = module_file(connector_module)
    module_root = Path.rootname(module_file)

    workspace_lockfile_path = resolve_workspace_lockfile_path(workspace_root)

    base_context = %{
      connector_name: connector_name,
      connector_display_name: connector_display_name(connector_name),
      connector_module: connector_module,
      project_module: project_module,
      package_root: package_root,
      package_root_relative: Path.relative_to(package_root, workspace_root),
      workspace_root: workspace_root,
      project_name: project_name,
      app_name: "jido_integration_v2_#{connector_name}",
      module_file: module_file,
      conformance_module: connector_module <> ".Conformance",
      conformance_file: Path.join(module_root, "conformance.ex"),
      test_file: test_file(module_file, "_test.exs"),
      conformance_test_file: test_file(module_file, "_conformance_test.exs"),
      contracts_dep_path:
        relative_dep_path(package_root, Path.join(workspace_root, "core/contracts")),
      conformance_dep_path:
        relative_dep_path(package_root, Path.join(workspace_root, "core/conformance")),
      runtime_class: runtime_class,
      runtime_class_literal: inspect(runtime_class),
      generated_on: Date.utc_today() |> Date.to_iso8601(),
      workspace_lockfile_path: workspace_lockfile_path,
      include_mix_lock: not is_nil(workspace_lockfile_path)
    }

    runtime_context =
      runtime_context(
        runtime_class,
        connector_name,
        connector_module,
        module_root,
        package_root,
        workspace_root
      )

    Map.merge(base_context, runtime_context)
  end

  defp runtime_context(
         :direct,
         connector_name,
         connector_module,
         module_root,
         package_root,
         workspace_root
       ) do
    capability_id = "#{connector_name}.sample.perform"
    required_scope = "#{connector_name}:run"
    run_id = "run-#{connector_name}-direct"
    attempt_id = "#{run_id}:1"
    handler_module = connector_module <> ".Actions.Perform"
    auth_token = "direct-demo-token"

    %{
      runtime_dep_path:
        relative_dep_path(package_root, Path.join(workspace_root, "core/direct_runtime")),
      jido_action_dep_path:
        relative_dep_path(package_root, Path.join(workspace_root, "jido_action")),
      handler_module: handler_module,
      handler_alias: "Perform",
      handler_file: Path.join(module_root, "actions/perform.ex"),
      handler_behaviour: "Jido.Action",
      handler_template: "handler_direct.ex.eex",
      package_description: "Scaffolded direct connector package for the greenfield platform",
      capability_id: capability_id,
      capability_kind_literal: ":operation",
      transport_profile_literal: ":action",
      required_scope: required_scope,
      environment_allowed_literal: "[:dev, :test]",
      sandbox_level_literal: ":standard",
      sandbox_egress_literal: ":restricted",
      sandbox_approvals_literal: ":auto",
      sandbox_file_scope_literal: "nil",
      allowed_tools_literal: inspect([capability_id]),
      manifest_test_name: "publishes a direct capability manifest",
      runtime_dependency_app: :jido_integration_v2_direct_runtime,
      direct_runtime: true,
      session_runtime: false,
      stream_runtime: false,
      fixture_input_literal: inspect(%{message: "hello from scaffold"}, pretty: true),
      fixture_context_literal:
        inspect(%{run_id: run_id, attempt_id: attempt_id}, pretty: true, limit: :infinity),
      fixture_credential_ref_literal:
        inspect(
          %{id: "cred-#{connector_name}", subject: "operator", scopes: [required_scope]},
          pretty: true,
          limit: :infinity
        ),
      fixture_credential_lease_literal:
        inspect(
          %{
            lease_id: "lease-#{connector_name}",
            credential_ref_id: "cred-#{connector_name}",
            subject: "operator",
            scopes: [required_scope],
            payload: %{api_token: auth_token},
            issued_at: ~U[2026-03-12 00:00:00Z],
            expires_at: ~U[2026-03-12 00:05:00Z]
          },
          pretty: true,
          limit: :infinity
        ),
      fixture_expect_output_literal:
        inspect(
          %{
            message: "hello from scaffold",
            handled_by: "operator",
            auth_binding: fixture_digest(auth_token)
          },
          pretty: true,
          limit: :infinity
        ),
      fixture_event_types_literal:
        inspect(
          [
            "attempt.started",
            "connector.#{connector_name}.sample.completed",
            "attempt.completed"
          ],
          pretty: true,
          limit: :infinity
        ),
      fixture_artifact_types_literal: "[:tool_output]",
      fixture_artifact_keys_literal:
        inspect(
          ["#{connector_name}/#{run_id}/#{attempt_id}/perform.term"],
          pretty: true,
          limit: :infinity
        ),
      conformance_event_type: "connector.#{connector_name}.sample.completed",
      fixture_auth_binding: fixture_digest(auth_token),
      include_runtime_metadata: false,
      runtime_driver_id: nil,
      migration_runtime_shim: false,
      publish_ingress_definitions: false,
      ingress_definitions_literal: "[]",
      fixture_run_id: run_id,
      fixture_attempt_id: attempt_id
    }
  end

  defp files(context) do
    base_files = [
      {"formatter.exs.eex", ".formatter.exs"},
      {"gitignore.eex", ".gitignore"},
      {"README.md.eex", "README.md"},
      {"mix.exs.eex", "mix.exs"},
      {"connector.ex.eex", context.module_file},
      {context.handler_template, context.handler_file},
      {"conformance.ex.eex", context.conformance_file},
      {"test_helper.exs.eex", "test/test_helper.exs"},
      {"connector_test.exs.eex", context.test_file},
      {"conformance_test.exs.eex", context.conformance_test_file}
    ]

    if is_binary(context.workspace_lockfile_path) and
         File.exists?(context.workspace_lockfile_path) do
      base_files ++ [{:workspace_lockfile, "mix.lock"}]
    else
      base_files
    end
  end

  defp ensure_package_root_available!(context) do
    if File.exists?(context.package_root) do
      Mix.raise("Target directory already exists: #{context.package_root_relative}")
    end
  end

  defp normalize_connector_name!(connector_name) do
    connector_name = connector_name |> to_string() |> String.trim()

    if Regex.match?(~r/^[a-z][a-z0-9_]*$/, connector_name) do
      connector_name
    else
      Mix.raise(
        "Invalid connector name: #{connector_name}. Use lowercase letters, numbers, and underscores only."
      )
    end
  end

  defp resolve_runtime_class!(runtime_class)
       when is_atom(runtime_class) and runtime_class in @runtime_classes,
       do: runtime_class

  defp resolve_runtime_class!(runtime_class) do
    runtime_class =
      runtime_class
      |> to_string()
      |> String.trim()
      |> String.downcase()
      |> String.to_existing_atom()

    if runtime_class in @runtime_classes do
      runtime_class
    else
      invalid_runtime_class!(runtime_class)
    end
  rescue
    ArgumentError -> invalid_runtime_class!(runtime_class)
  end

  @spec invalid_runtime_class!(term()) :: no_return()
  defp invalid_runtime_class!(runtime_class) do
    supported =
      @runtime_classes
      |> Enum.map_join(", ", &Atom.to_string/1)

    Mix.raise("Invalid runtime class: #{runtime_class}. Must be one of: #{supported}")
  end

  @spec ensure_scaffoldable_runtime_class!(runtime_class(), String.t()) :: :ok | no_return()
  defp ensure_scaffoldable_runtime_class!(:direct, _connector_name), do: :ok

  defp ensure_scaffoldable_runtime_class!(runtime_class, connector_name)
       when runtime_class in [:session, :stream] do
    runtime_label = runtime_class |> Atom.to_string() |> String.capitalize()

    legacy_bridge =
      case runtime_class do
        :session -> "integration_session_bridge"
        :stream -> "integration_stream_bridge"
      end

    Mix.raise("""
    #{runtime_label} connector scaffolds are intentionally disabled in Phase 0.

    New runtime-boundary work must not generate the legacy `#{legacy_bridge}` path.
    Compose `#{connector_name}` manually against the real Harness target kernels instead:

    - `asm`
    - `jido_session`

    The workspace scaffold currently supports direct connectors only.
    """)
  end

  defp normalize_module_name(module_name) do
    module_name
    |> to_string()
    |> String.trim()
    |> String.trim_leading("Elixir.")
  end

  defp default_module_name(connector_name) do
    "Jido.Integration.V2.Connectors." <> Macro.camelize(connector_name)
  end

  defp resolve_package_root(workspace_root, connector_name, nil) do
    Path.expand(Path.join("connectors", connector_name), workspace_root)
  end

  defp resolve_package_root(workspace_root, _connector_name, path) do
    Path.expand(path, workspace_root)
  end

  defp resolve_project_name(connector_name, nil) do
    "Jido Integration V2 #{connector_display_name(connector_name)} Connector"
  end

  defp resolve_project_name(_connector_name, package_name) do
    package_name = package_name |> to_string() |> String.trim()

    if package_name == "" do
      Mix.raise("--package-name must not be empty")
    else
      package_name
    end
  end

  defp connector_display_name(connector_name) do
    connector_name
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp module_file(module_name) do
    "lib/" <> Macro.underscore(module_name) <> ".ex"
  end

  defp test_file(module_file, suffix) do
    module_file
    |> String.trim_leading("lib/")
    |> Path.rootname()
    |> then(&"test/#{&1}#{suffix}")
  end

  defp relative_dep_path(package_root, target_path) do
    package_segments = package_root |> Path.expand() |> Path.split()
    target_segments = target_path |> Path.expand() |> Path.split()
    common_length = common_prefix_length(package_segments, target_segments)

    relative_segments =
      List.duplicate("..", length(package_segments) - common_length) ++
        Enum.drop(target_segments, common_length)

    case relative_segments do
      [] -> "."
      segments -> Path.join(segments)
    end
  end

  defp common_prefix_length(left, right) do
    left
    |> Enum.zip(right)
    |> Enum.take_while(fn {left_segment, right_segment} -> left_segment == right_segment end)
    |> length()
  end

  defp template_path(template_name) do
    Path.join(template_root(), template_name)
  end

  defp template_root do
    Path.expand("../../../../priv/templates/jido.integration.new", __DIR__)
  end

  defp fixture_digest(value) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, value), case: :lower)
  end

  defp resolve_workspace_lockfile_path(workspace_root) do
    candidates = [
      Path.join(workspace_root, "mix.lock"),
      Path.join(Monorepo.root_dir(), "mix.lock")
    ]

    Enum.find(candidates, &File.exists?/1)
  end
end
