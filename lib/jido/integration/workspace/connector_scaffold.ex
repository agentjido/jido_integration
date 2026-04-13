defmodule Jido.Integration.Workspace.ConnectorScaffold do
  @moduledoc false

  import Mix.Generator

  @runtime_classes [:direct, :session, :stream]
  @default_runtime_class :direct
  @target_runtime_drivers %{
    session: ["asm", "jido_session"],
    stream: ["asm"]
  }

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

    workspace_root =
      opts |> Keyword.get(:workspace_root, repo_root()) |> Path.expand()

    runtime_class =
      resolve_runtime_class!(Keyword.get(opts, :runtime_class, @default_runtime_class))

    runtime_driver_id =
      resolve_runtime_driver!(runtime_class, Keyword.get(opts, :runtime_driver))

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
      conformance_runtime_control_driver_module:
        if(runtime_class in [:session, :stream],
          do: connector_module <> ".ConformanceRuntimeControlDriver",
          else: nil
        ),
      conformance_runtime_control_driver_alias:
        if(runtime_class in [:session, :stream],
          do:
            connector_module
            |> Kernel.<>(".ConformanceRuntimeControlDriver")
            |> String.split(".")
            |> List.last(),
          else: nil
        ),
      conformance_file: Path.join(module_root, "conformance.ex"),
      test_file: test_file(module_file, "_test.exs"),
      conformance_test_file: test_file(module_file, "_conformance_test.exs"),
      generated_actions_file: Path.join(module_root, "generated/actions.ex"),
      generated_sensors_file: Path.join(module_root, "generated/sensors.ex"),
      generated_plugin_file: Path.join(module_root, "generated/plugin.ex"),
      trigger_handler_module: connector_module <> ".Triggers.SampleDetected",
      trigger_handler_alias: "SampleDetected",
      trigger_handler_file: Path.join(module_root, "triggers/sample_detected.ex"),
      contracts_dep_path:
        relative_dep_path(package_root, Path.join(workspace_root, "core/contracts")),
      consumer_surfaces_dep_path:
        relative_dep_path(package_root, Path.join(workspace_root, "core/consumer_surfaces")),
      direct_runtime_dep_path:
        relative_dep_path(package_root, Path.join(workspace_root, "core/direct_runtime")),
      conformance_dep_path:
        relative_dep_path(package_root, Path.join(workspace_root, "core/conformance")),
      jido_runtime_control_dep_path:
        relative_dep_path(package_root, Path.join(workspace_root, "core/runtime_control")),
      runtime_class: runtime_class,
      runtime_class_literal: inspect(runtime_class),
      runtime_families_literal: inspect(runtime_families(runtime_class)),
      runtime_driver_id: runtime_driver_id,
      runtime_driver_atom_literal:
        if(is_binary(runtime_driver_id),
          do: inspect(String.to_atom(runtime_driver_id)),
          else: nil
        ),
      include_runtime_drivers: runtime_class in [:session, :stream],
      include_test_support: runtime_class in [:session, :stream],
      generated_on: Date.utc_today() |> Date.to_iso8601(),
      workspace_lockfile_path: workspace_lockfile_path,
      include_mix_lock: not is_nil(workspace_lockfile_path),
      trigger_id: "#{connector_name}.sample.detected",
      trigger_name: "sample_detected",
      trigger_display_name: "Sample detected",
      trigger_description: "Projection-ready poll trigger skeleton for the scaffolded connector",
      trigger_signal_type: "#{connector_name}.sample.detected",
      trigger_signal_source: "/ingress/poll/#{connector_name}/sample.detected",
      trigger_consumer_surface_sensor_name: "sample_detected",
      trigger_jido_sensor_name: "#{connector_name}_sample_detected_sensor",
      trigger_polling_literal:
        inspect(%{default_interval_ms: 60_000, min_interval_ms: 5_000, jitter: false},
          pretty: true,
          limit: :infinity
        ),
      trigger_checkpoint_literal:
        inspect(%{strategy: :timestamp_cursor, field: "observed_at", partition_key: "workspace"},
          pretty: true,
          limit: :infinity
        ),
      trigger_dedupe_literal:
        inspect(%{strategy: :resource_version, fields: ["resource_id", "observed_at"]},
          pretty: true,
          limit: :infinity
        ),
      trigger_config_schema_literal:
        """
          Zoi.object(%{
            window_minutes: Zoi.integer() |> Zoi.default(15)
          })
        """
        |> String.trim_trailing(),
      trigger_signal_schema_literal:
        """
          Zoi.object(%{
            resource_id: Zoi.string(),
            message: Zoi.string(),
            observed_at: Zoi.string()
          })
        """
        |> String.trim_trailing(),
      ingress_definitions_literal:
        inspect(
          [
            %{
              source: :poll,
              connector_id: connector_name,
              trigger_id: "#{connector_name}.sample.detected",
              capability_id: "#{connector_name}.sample.detected",
              signal_type: "#{connector_name}.sample.detected",
              signal_source: "/ingress/poll/#{connector_name}/sample.detected"
            }
          ],
          pretty: true,
          limit: :infinity
        )
    }

    runtime_context =
      runtime_context(
        runtime_class,
        connector_name,
        connector_module,
        module_root,
        package_root,
        workspace_root,
        runtime_driver_id
      )

    Map.merge(base_context, runtime_context)
  end

  defp runtime_context(
         :direct,
         connector_name,
         connector_module,
         module_root,
         package_root,
         workspace_root,
         _runtime_driver_id
       ) do
    capability_id = "#{connector_name}.sample.perform"
    required_scope = "#{connector_name}:run"
    run_id = "run-#{connector_name}-direct"
    attempt_id = "#{run_id}:1"
    handler_module = connector_module <> ".Actions.Perform"
    auth_token = "direct-demo-token"
    auth_profile_id = default_auth_profile_id()

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
      operation_id: capability_id,
      capability_id: capability_id,
      operation_name: "sample_perform",
      operation_display_name: "Sample perform",
      operation_description: "Placeholder authored operation for the scaffolded connector",
      common_action_normalized_id: "sample.perform",
      transport_profile_literal: ":action",
      upstream_literal: "%{transport: :action}",
      required_scope: required_scope,
      environment_allowed_literal: "[:dev, :test]",
      sandbox_level_literal: ":standard",
      sandbox_egress_literal: ":restricted",
      sandbox_approvals_literal: ":auto",
      sandbox_file_scope_literal: "nil",
      allowed_tools_literal: inspect([capability_id]),
      input_schema_literal:
        """
          Zoi.object(%{
            message: Zoi.string()
          })
        """
        |> String.trim_trailing(),
      output_schema_literal:
        """
          Zoi.object(%{
            message: Zoi.string(),
            handled_by: Zoi.string(),
            auth_binding: Zoi.string()
          })
        """
        |> String.trim_trailing(),
      generated_action_name: "#{connector_name}_sample_perform",
      manifest_test_name:
        "publishes projection-ready direct operation and poll trigger contracts with generated consumer surfaces",
      direct_runtime: true,
      session_runtime: false,
      stream_runtime: false,
      non_direct_runtime: false,
      fixture_input_literal: inspect(%{message: "hello from scaffold"}, pretty: true),
      fixture_context_literal:
        inspect(%{run_id: run_id, attempt_id: attempt_id}, pretty: true, limit: :infinity),
      fixture_credential_ref_literal:
        inspect(
          %{
            id: "cred-#{connector_name}",
            subject: "operator",
            profile_id: auth_profile_id,
            scopes: [required_scope],
            lease_fields: ["api_token"]
          },
          pretty: true,
          limit: :infinity
        ),
      fixture_credential_lease_literal:
        inspect(
          %{
            lease_id: "lease-#{connector_name}",
            credential_ref_id: "cred-#{connector_name}",
            subject: "operator",
            profile_id: auth_profile_id,
            scopes: [required_scope],
            payload: %{api_token: auth_token},
            lease_fields: ["api_token"],
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
      runtime_family_literal: nil,
      runtime_provider_literal: nil,
      runtime_options_literal: "%{}",
      auth_lease_field: "api_token",
      auth_lease_field_literal: ":api_token",
      conformance_runtime_control_driver_file: nil,
      publish_ingress_definitions: true,
      fixture_run_id: run_id,
      fixture_attempt_id: attempt_id
    }
    |> Map.merge(auth_contract_context(required_scope, "api_token"))
  end

  defp runtime_context(
         :session,
         connector_name,
         connector_module,
         module_root,
         _package_root,
         _workspace_root,
         runtime_driver_id
       ) do
    capability_id = "#{connector_name}.sample.session"
    required_scope = "#{connector_name}:session"
    run_id = "run-#{connector_name}-session"
    attempt_id = "#{run_id}:1"
    handler_module = connector_module <> ".Handler"
    auth_token = "session-demo-token"
    auth_profile_id = default_auth_profile_id()
    workspace = "/workspaces/#{connector_name}"

    %{
      handler_module: handler_module,
      handler_alias: "Handler",
      handler_file: Path.join(module_root, "handler.ex"),
      handler_template: "handler_non_direct.ex.eex",
      package_description: "Scaffolded session connector package for the greenfield platform",
      operation_id: capability_id,
      capability_id: capability_id,
      operation_name: "sample_session",
      operation_display_name: "Sample session",
      operation_description: "Placeholder session capability for the scaffolded connector",
      common_action_normalized_id: "sample.session",
      transport_profile_literal: ":stdio",
      upstream_literal: "%{transport: :stdio}",
      required_scope: required_scope,
      environment_allowed_literal: "[:prod]",
      sandbox_level_literal: ":strict",
      sandbox_egress_literal: ":restricted",
      sandbox_approvals_literal: ":manual",
      sandbox_file_scope_literal: inspect(workspace),
      allowed_tools_literal: inspect([capability_id]),
      input_schema_literal:
        """
          Zoi.object(%{
            prompt: Zoi.string()
          })
        """
        |> String.trim_trailing(),
      output_schema_literal:
        """
          Zoi.object(%{
            reply: Zoi.string(),
            auth_binding: Zoi.string(),
            runtime_driver: Zoi.string()
          })
        """
        |> String.trim_trailing(),
      generated_action_name: "#{connector_name}_sample_session",
      manifest_test_name:
        "publishes projection-ready session operation and poll trigger contracts with explicit runtime-control metadata",
      direct_runtime: false,
      session_runtime: true,
      stream_runtime: false,
      non_direct_runtime: true,
      fixture_input_literal: inspect(%{prompt: "hello from scaffold"}, pretty: true),
      fixture_context_literal:
        inspect(%{run_id: run_id, attempt_id: attempt_id}, pretty: true, limit: :infinity),
      fixture_credential_ref_literal:
        inspect(
          %{
            id: "cred-#{connector_name}",
            subject: "operator",
            profile_id: auth_profile_id,
            scopes: [required_scope],
            lease_fields: ["access_token"]
          },
          pretty: true,
          limit: :infinity
        ),
      fixture_credential_lease_literal:
        inspect(
          %{
            lease_id: "lease-#{connector_name}",
            credential_ref_id: "cred-#{connector_name}",
            subject: "operator",
            profile_id: auth_profile_id,
            scopes: [required_scope],
            payload: %{access_token: auth_token},
            lease_fields: ["access_token"],
            issued_at: ~U[2026-03-12 00:00:00Z],
            expires_at: ~U[2026-03-12 00:05:00Z]
          },
          pretty: true,
          limit: :infinity
        ),
      fixture_expect_output_literal:
        inspect(
          %{
            reply: "#{runtime_driver_id}(operator): hello from scaffold",
            auth_binding: fixture_digest(auth_token),
            runtime_driver: runtime_driver_id
          },
          pretty: true,
          limit: :infinity
        ),
      fixture_event_types_literal:
        inspect(
          [
            "session.started",
            "connector.#{connector_name}.session.completed"
          ],
          pretty: true,
          limit: :infinity
        ),
      fixture_artifact_types_literal: "[:event_log]",
      fixture_artifact_keys_literal:
        inspect(
          ["#{connector_name}/#{run_id}/#{attempt_id}/session.term"],
          pretty: true,
          limit: :infinity
        ),
      conformance_event_type: "connector.#{connector_name}.session.completed",
      fixture_auth_binding: fixture_digest(auth_token),
      include_runtime_metadata: true,
      runtime_family_literal:
        inspect(
          %{
            session_affinity: :connection,
            resumable: true,
            approval_required: true,
            stream_capable: true,
            lifecycle_owner: String.to_atom(runtime_driver_id),
            runtime_ref: :session
          },
          pretty: true,
          limit: :infinity
        ),
      runtime_provider_literal: nil,
      runtime_options_literal: "%{}",
      auth_lease_field: "access_token",
      auth_lease_field_literal: ":access_token",
      conformance_runtime_control_driver_file:
        Path.join(module_root, "conformance_runtime_control_driver.ex"),
      publish_ingress_definitions: true,
      fixture_run_id: run_id,
      fixture_attempt_id: attempt_id
    }
    |> Map.merge(auth_contract_context(required_scope, "access_token"))
  end

  defp runtime_context(
         :stream,
         connector_name,
         connector_module,
         module_root,
         _package_root,
         _workspace_root,
         runtime_driver_id
       ) do
    capability_id = "#{connector_name}.sample.stream"
    required_scope = "#{connector_name}:stream"
    run_id = "run-#{connector_name}-stream"
    attempt_id = "#{run_id}:1"
    handler_module = connector_module <> ".Handler"
    api_key = "stream-demo-key"
    auth_profile_id = default_auth_profile_id()

    %{
      handler_module: handler_module,
      handler_alias: "Handler",
      handler_file: Path.join(module_root, "handler.ex"),
      handler_template: "handler_non_direct.ex.eex",
      package_description: "Scaffolded stream connector package for the greenfield platform",
      operation_id: capability_id,
      capability_id: capability_id,
      operation_name: "sample_stream",
      operation_display_name: "Sample stream",
      operation_description: "Placeholder stream capability for the scaffolded connector",
      common_action_normalized_id: "sample.stream",
      transport_profile_literal: ":stream",
      upstream_literal: "%{transport: :stream}",
      required_scope: required_scope,
      environment_allowed_literal: "[:prod]",
      sandbox_level_literal: ":standard",
      sandbox_egress_literal: ":blocked",
      sandbox_approvals_literal: ":auto",
      sandbox_file_scope_literal: "nil",
      allowed_tools_literal: inspect([capability_id]),
      input_schema_literal:
        """
          Zoi.object(%{
            topic: Zoi.string(),
            batch_size: Zoi.integer()
          })
        """
        |> String.trim_trailing(),
      output_schema_literal:
        """
          Zoi.object(%{
            topic: Zoi.string(),
            batch_size: Zoi.integer(),
            cursor: Zoi.integer(),
            items:
              Zoi.list(
                Zoi.object(%{
                  seq: Zoi.integer(),
                  topic: Zoi.string()
                })
              ),
            auth_binding: Zoi.string(),
            runtime_driver: Zoi.string()
          })
        """
        |> String.trim_trailing(),
      generated_action_name: "#{connector_name}_sample_stream",
      manifest_test_name:
        "publishes projection-ready stream operation and poll trigger contracts with explicit runtime-control metadata",
      direct_runtime: false,
      session_runtime: false,
      stream_runtime: true,
      non_direct_runtime: true,
      fixture_input_literal:
        inspect(%{topic: "hello from scaffold", batch_size: 2}, pretty: true),
      fixture_context_literal:
        inspect(%{run_id: run_id, attempt_id: attempt_id}, pretty: true, limit: :infinity),
      fixture_credential_ref_literal:
        inspect(
          %{
            id: "cred-#{connector_name}",
            subject: "operator",
            profile_id: auth_profile_id,
            scopes: [required_scope],
            lease_fields: ["api_key"]
          },
          pretty: true,
          limit: :infinity
        ),
      fixture_credential_lease_literal:
        inspect(
          %{
            lease_id: "lease-#{connector_name}",
            credential_ref_id: "cred-#{connector_name}",
            subject: "operator",
            profile_id: auth_profile_id,
            scopes: [required_scope],
            payload: %{api_key: api_key},
            lease_fields: ["api_key"],
            issued_at: ~U[2026-03-12 00:00:00Z],
            expires_at: ~U[2026-03-12 00:05:00Z]
          },
          pretty: true,
          limit: :infinity
        ),
      fixture_expect_output_literal:
        inspect(
          %{
            topic: "hello from scaffold",
            batch_size: 2,
            cursor: 2,
            items: [
              %{seq: 1, topic: "hello from scaffold"},
              %{seq: 2, topic: "hello from scaffold"}
            ],
            auth_binding: fixture_digest(api_key),
            runtime_driver: runtime_driver_id
          },
          pretty: true,
          limit: :infinity
        ),
      fixture_event_types_literal:
        inspect(
          [
            "stream.started",
            "connector.#{connector_name}.stream.completed"
          ],
          pretty: true,
          limit: :infinity
        ),
      fixture_artifact_types_literal: "[:log]",
      fixture_artifact_keys_literal:
        inspect(
          ["#{connector_name}/#{run_id}/#{attempt_id}/stream_2.term"],
          pretty: true,
          limit: :infinity
        ),
      conformance_event_type: "connector.#{connector_name}.stream.completed",
      fixture_auth_binding: fixture_digest(api_key),
      include_runtime_metadata: true,
      runtime_family_literal:
        inspect(
          %{
            session_affinity: :target,
            resumable: false,
            approval_required: false,
            stream_capable: true,
            lifecycle_owner: String.to_atom(runtime_driver_id),
            runtime_ref: :session
          },
          pretty: true,
          limit: :infinity
        ),
      runtime_provider_literal: nil,
      runtime_options_literal: "%{}",
      auth_lease_field: "api_key",
      auth_lease_field_literal: ":api_key",
      conformance_runtime_control_driver_file:
        Path.join(module_root, "conformance_runtime_control_driver.ex"),
      publish_ingress_definitions: true,
      fixture_run_id: run_id,
      fixture_attempt_id: attempt_id
    }
    |> Map.merge(auth_contract_context(required_scope, "api_key"))
  end

  defp default_auth_profile_id, do: "default_manual_secret"

  defp auth_contract_context(required_scope, lease_field) do
    supported_profile = %{
      id: default_auth_profile_id(),
      auth_type: :api_token,
      subject_kind: :user,
      install_required: false,
      grant_types: [:manual_token],
      durable_secret_fields: [lease_field],
      lease_fields: [lease_field],
      management_modes: [:external_secret, :manual],
      callback_required: false,
      pkce_required: false,
      refresh_supported: false,
      revoke_supported: false,
      reauth_supported: false,
      external_secret_supported: true,
      external_secret_lease_fields: [],
      required_scopes: [required_scope],
      docs_refs: [],
      metadata: %{}
    }

    install = %{
      required: false,
      profiles: [],
      hosted_callback_supported: false,
      state_required: false,
      pkce_supported: false,
      metadata: %{}
    }

    reauth = %{
      supported: false,
      profiles: [],
      hosted_callback_supported: false,
      state_required: false,
      pkce_supported: false,
      metadata: %{}
    }

    %{
      auth_profile_id: default_auth_profile_id(),
      auth_supported_profiles_literal:
        inspect([supported_profile], pretty: true, limit: :infinity),
      auth_default_profile_literal: inspect(default_auth_profile_id()),
      auth_install_literal: inspect(install, pretty: true, limit: :infinity),
      auth_reauth_literal: inspect(reauth, pretty: true, limit: :infinity),
      auth_management_modes_literal:
        inspect([:external_secret, :manual], pretty: true, limit: :infinity),
      auth_requested_scopes_literal: inspect([required_scope], pretty: true, limit: :infinity),
      auth_durable_secret_fields_literal: inspect([lease_field], pretty: true, limit: :infinity),
      auth_lease_fields_literal: inspect([lease_field], pretty: true, limit: :infinity)
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
      {"trigger_handler.ex.eex", context.trigger_handler_file},
      {"generated_actions.ex.eex", context.generated_actions_file},
      {"generated_sensors.ex.eex", context.generated_sensors_file},
      {"generated_plugin.ex.eex", context.generated_plugin_file},
      {"conformance.ex.eex", context.conformance_file},
      {"test_helper.exs.eex", "test/test_helper.exs"},
      {"connector_test.exs.eex", context.test_file},
      {"conformance_test.exs.eex", context.conformance_test_file}
    ]

    base_files =
      if context.include_test_support do
        base_files ++
          [
            {"conformance_runtime_control_driver.ex.eex",
             context.conformance_runtime_control_driver_file}
          ]
      else
        base_files
      end

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

  defp resolve_runtime_driver!(:direct, nil), do: nil

  defp resolve_runtime_driver!(:direct, _runtime_driver) do
    Mix.raise("--runtime-driver is only valid for session or stream scaffolds")
  end

  defp resolve_runtime_driver!(runtime_class, nil) when runtime_class in [:session, :stream] do
    supported =
      @target_runtime_drivers
      |> Map.fetch!(runtime_class)
      |> Enum.join(", ")

    runtime_label = runtime_class |> Atom.to_string() |> String.capitalize()

    Mix.raise(
      "#{runtime_label} connector scaffolds require --runtime-driver. Choose one of: #{supported}"
    )
  end

  defp resolve_runtime_driver!(runtime_class, runtime_driver)
       when runtime_class in [:session, :stream] do
    runtime_driver = runtime_driver |> to_string() |> String.trim()
    supported = Map.fetch!(@target_runtime_drivers, runtime_class)

    if runtime_driver in supported do
      runtime_driver
    else
      Mix.raise(
        "Invalid runtime driver: #{runtime_driver} for #{runtime_class}. Must be one of: #{Enum.join(supported, ", ")}"
      )
    end
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
      Path.join(repo_root(), "mix.lock")
    ]

    Enum.find(candidates, &File.exists?/1)
  end

  defp repo_root do
    Path.expand("../../../..", __DIR__)
  end

  defp runtime_families(:direct), do: [:direct]
  defp runtime_families(runtime_class), do: [:direct, runtime_class]
end
