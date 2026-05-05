defmodule Jido.Integration.V2.Connectors.Amp do
  @moduledoc """
  Amp CLI connector lane for governed provider execution.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.ConnectorRegistry
  alias Jido.Integration.V2.Connectors.Amp.Handler
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.ToolContracts

  @owner_repo "jido_integration"
  @package_path "connectors/amp"

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: "amp",
      auth:
        AuthSpec.new!(%{
          binding_kind: :provider_account,
          auth_type: :native_cli_assertion,
          install: %{required: true},
          reauth: %{supported: true},
          requested_scopes: ["amp:command", "amp:stream", "amp:mcp", "amp:permissions"],
          lease_fields: ["native_auth_assertion_ref", "credential_lease_ref"],
          secret_names: []
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: "Amp",
          description: "Amp CLI provider connector with governed authority refs",
          category: "developer_tools",
          tags: ["amp", "cli", "mcp"],
          docs_refs: [],
          maturity: :experimental,
          publication: :internal
        }),
      operations: [
        operation(
          "amp.command.run",
          "command_run",
          "Run Amp command",
          "Runs an Amp CLI command through materialized governed authority",
          ["amp:command"],
          :provider_native_tool,
          :direct
        ),
        operation(
          "amp.stream.run",
          "stream_run",
          "Stream Amp command",
          "Streams Amp CLI output through materialized governed authority",
          ["amp:stream"],
          :provider_native_tool,
          :stream
        ),
        operation(
          "amp.mcp.status",
          "mcp_status",
          "Read Amp MCP status",
          "Reads Amp MCP status with ref-only admission and native assertion refs",
          ["amp:mcp"],
          :connector_tool,
          :direct
        ),
        operation(
          "amp.permissions.assert",
          "permissions_assert",
          "Assert Amp permissions",
          "Asserts Amp permissions metadata without projecting permission file contents",
          ["amp:permissions"],
          :read_only_observation,
          :direct
        )
      ],
      triggers: [],
      runtime_families: [:direct, :stream]
    })
  end

  @spec registry_entry(map() | keyword()) :: {:ok, ConnectorRegistry.entry()} | {:error, term()}
  def registry_entry(attrs \\ []) do
    attrs
    |> Map.new()
    |> Map.merge(registry_attrs())
    |> ConnectorRegistry.register()
  end

  @spec tool_contracts() :: [ToolContracts.t()]
  def tool_contracts do
    [
      tool_contract!("tool-contract://amp/command", :provider_native_tool, [
        "prompt",
        "thread_ref"
      ]),
      tool_contract!("tool-contract://amp/mcp", :connector_tool, ["server_name"]),
      tool_contract!("tool-contract://amp/permissions", :read_only_observation, ["permission_ref"])
    ]
  end

  defp operation(operation_id, name, display_name, description, scopes, category, runtime_class) do
    OperationSpec.new!(%{
      operation_id: operation_id,
      name: name,
      display_name: display_name,
      description: description,
      runtime_class: runtime_class,
      transport_mode: :cli,
      handler: Handler,
      input_schema: input_schema(),
      output_schema: output_schema(),
      permissions: %{required_scopes: scopes},
      runtime: %{driver: "cli_subprocess_core", provider: :amp},
      policy: %{
        environment: %{allowed: [:prod]},
        sandbox: %{level: :strict, egress: :restricted, approvals: :manual}
      },
      upstream: %{protocol: :cli},
      consumer_surface: %{
        mode: :common,
        normalized_id: operation_id,
        action_name: action_name(operation_id)
      },
      schema_policy: %{input: :defined, output: :defined},
      jido: %{action: %{name: action_name(operation_id)}},
      metadata: %{
        runtime_family: runtime_family(runtime_class),
        tool_contract_ref: "tool-contract://amp/#{name}",
        tool_category: category,
        native_auth_assertion_required: true,
        connector_binding_required: true,
        credential_lease_required: true,
        target_ref_required: true,
        operation_policy_required: true,
        redaction: :ref_only
      }
    })
  end

  defp registry_attrs do
    %{
      tenant_ref: "tenant://tenant-1",
      policy_revision_ref: "policy-revision://tenant-1/auth/1",
      provider_ref: "provider://amp",
      provider_family: "cli",
      provider_account_ref: "provider-account://tenant-1/amp/default",
      provider_account_status: :asserted,
      connector_ref: "connector://amp/cli",
      connector_instance_ref: "connector-instance://tenant-1/amp/cli",
      connector_category: :official_connector,
      credential_handle_ref: "credential-handle://tenant-1/amp/native-cli",
      target_ref: "target://tenant-1/cli/amp",
      operation_policy_ref: "operation-policy://tenant-1/amp/cli",
      owner_repo: @owner_repo,
      package_path: @package_path,
      conformance_suite_ref: "conformance-suite://amp/cli",
      env_remediation_state: :governed_clean,
      auth_methods: [:native_cli_login, :mcp_oauth_state, :permissions_config],
      supported_operations: [:command_run, :stream_run, :mcp_status, :permissions_assert],
      binding_shape: %{
        requires_connector_binding_ref: true,
        requires_native_auth_assertion_ref: true
      },
      product_boundary: %{governed_hot_path: true, standalone_preserved: true}
    }
  end

  defp tool_contract!(ref, category, payload_keys) do
    {:ok, contract} =
      ToolContracts.new(
        contract_ref: ref,
        category: category,
        auth_source: auth_source(category),
        execution_authority: execution_authority(category),
        redaction_class: :provider_tool_metadata,
        allowed_payload_keys: payload_keys,
        metadata: %{provider: :amp}
      )

    contract
  end

  defp auth_source(:read_only_observation), do: :read_only_ref
  defp auth_source(_category), do: :provider_native_assertion_ref

  defp execution_authority(:connector_tool), do: :connector_operation
  defp execution_authority(:read_only_observation), do: :read_only_projection
  defp execution_authority(_category), do: :provider_native_runtime

  defp runtime_family(:stream) do
    %{
      session_affinity: :target,
      resumable: false,
      approval_required: true,
      stream_capable: true,
      lifecycle_owner: :cli_subprocess_core,
      runtime_ref: :run
    }
  end

  defp runtime_family(_runtime_class), do: nil

  defp input_schema do
    Zoi.object(%{
      prompt: Zoi.string() |> Zoi.optional(),
      thread_ref: Zoi.string() |> Zoi.optional(),
      server_name: Zoi.string() |> Zoi.optional(),
      permission_ref: Zoi.string() |> Zoi.optional()
    })
  end

  defp output_schema do
    Zoi.object(%{
      status: Zoi.atom(),
      admission_ref: Zoi.string(),
      redaction_ref: Zoi.string()
    })
  end

  defp action_name(operation_id), do: String.replace(operation_id, ".", "_")
end

defmodule Jido.Integration.V2.Connectors.Amp.Handler do
  @moduledoc """
  Marker handler for Amp CLI governed operations.
  """
end

defmodule Jido.Integration.V2.Connectors.Amp.Conformance do
  @moduledoc false

  @spec fixtures() :: [map()]
  def fixtures do
    [
      %{
        capability_id: "amp.command.run",
        input: %{prompt: "inspect fixture"},
        expect: %{
          event_types: ["connector.amp.command.admitted"],
          artifact_types: [:admission_projection],
          refs: %{
            native_auth_assertion_ref: "native-auth-assertion://amp/fixture",
            credential_lease_ref: "credential-lease://amp/fixture",
            target_ref: "target://tenant-1/cli/amp",
            operation_policy_ref: "operation-policy://tenant-1/amp/cli"
          }
        }
      }
    ]
  end
end
