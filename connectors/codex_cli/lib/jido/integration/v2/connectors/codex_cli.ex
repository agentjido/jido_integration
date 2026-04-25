defmodule Jido.Integration.V2.Connectors.CodexCli do
  @moduledoc """
  Example external session connector package.

  This connector publishes the canonical session-family authored shape on the
  shared common consumer-surface spine through the `Jido.RuntimeControl` `asm`
  driver.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Connectors.CodexCli.Handler
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec

  @runtime_family %{
    session_affinity: :connection,
    resumable: true,
    approval_required: true,
    stream_capable: true,
    lifecycle_owner: :asm,
    runtime_ref: :session
  }

  @policy %{
    environment: %{allowed: [:prod]},
    sandbox: %{
      level: :strict,
      egress: :restricted,
      approvals: :manual,
      file_scope: "/workspaces/codex_cli"
    }
  }

  @runtime %{
    driver: "asm",
    provider: :codex,
    options: %{app_server: true}
  }

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: "codex_cli",
      auth:
        AuthSpec.new!(%{
          binding_kind: :connection_id,
          auth_type: :api_token,
          install: %{required: true},
          reauth: %{supported: false},
          requested_scopes: ["session:execute", "session:control", "session:tools"],
          lease_fields: ["access_token"],
          secret_names: []
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: "Codex CLI",
          description: "Example session connector package for interactive codex work",
          category: "developer_tools",
          tags: ["codex", "session"],
          docs_refs: [],
          maturity: :experimental,
          publication: :internal
        }),
      operations: [
        session_operation(
          "codex.session.approve",
          "session_approve",
          "Approve session request",
          "Approves or denies a pending Codex app-server approval",
          input_schema:
            Zoi.object(%{
              approval_id: Zoi.string(),
              decision: Zoi.enum([:allow, :deny, "allow", "deny"])
            }),
          output_schema: status_output_schema(),
          required_scopes: ["session:control"],
          metadata: %{codex_app_server: %{primary?: false, control: :approval}}
        ),
        session_operation(
          "codex.session.cancel",
          "session_cancel",
          "Cancel session run",
          "Cancels the active Codex app-server run for the session",
          input_schema:
            Zoi.object(%{
              run_id: Zoi.string() |> Zoi.optional()
            }),
          output_schema: status_output_schema(),
          required_scopes: ["session:control"],
          metadata: %{codex_app_server: %{primary?: false, control: :cancel}}
        ),
        session_operation(
          "codex.session.start",
          "session_start",
          "Start session",
          "Starts or reuses the ASM-owned Codex app-server session boundary",
          input_schema:
            Zoi.object(%{
              cwd: Zoi.string() |> Zoi.optional()
            }),
          output_schema: status_output_schema(),
          required_scopes: ["session:execute"],
          metadata: %{codex_app_server: %{primary?: false, control: :start}}
        ),
        session_operation(
          "codex.session.status",
          "session_status",
          "Session status",
          "Reads the current ASM-owned Codex app-server session status",
          input_schema:
            Zoi.object(%{
              session_id: Zoi.string() |> Zoi.optional()
            }),
          output_schema: status_output_schema(),
          required_scopes: ["session:control"],
          metadata: %{codex_app_server: %{primary?: false, control: :status}}
        ),
        session_operation(
          "codex.session.stream",
          "session_stream",
          "Stream session turn",
          "Streams a Codex app-server turn through ASM Runtime Control",
          runtime_class: :stream,
          input_schema: turn_input_schema(),
          output_schema: turn_output_schema(),
          required_scopes: ["session:execute"],
          metadata: %{codex_app_server: %{primary?: false, host_tools: :native}}
        ),
        session_operation(
          "codex.session.tool.respond",
          "session_tool_respond",
          "Respond to host tool",
          "Responds to a pending Codex app-server dynamic host-tool request",
          input_schema:
            Zoi.object(%{
              request_id: Zoi.string(),
              output: Zoi.any() |> Zoi.optional(),
              error: Zoi.any() |> Zoi.optional()
            }),
          output_schema: status_output_schema(),
          required_scopes: ["session:tools"],
          metadata: %{codex_app_server: %{primary?: false, control: :tool_response}}
        ),
        session_operation(
          "codex.session.turn",
          "session_turn",
          "Run session turn",
          "Runs the primary Codex app-server turn through ASM Runtime Control",
          input_schema: turn_input_schema(),
          output_schema: turn_output_schema(),
          required_scopes: ["session:execute"],
          metadata: %{codex_app_server: %{primary?: true, host_tools: :native}}
        )
      ],
      triggers: [],
      runtime_families: [:session, :stream]
    })
  end

  defp session_operation(operation_id, name, display_name, description, opts) do
    required_scopes = Keyword.fetch!(opts, :required_scopes)
    runtime_class = Keyword.get(opts, :runtime_class, :session)
    metadata = Keyword.get(opts, :metadata, %{})

    OperationSpec.new!(%{
      operation_id: operation_id,
      name: name,
      display_name: display_name,
      description: description,
      runtime_class: runtime_class,
      transport_mode: :app_server,
      handler: Handler,
      input_schema: Keyword.fetch!(opts, :input_schema),
      output_schema: Keyword.fetch!(opts, :output_schema),
      permissions: %{required_scopes: required_scopes},
      runtime: @runtime,
      policy: put_in(@policy, [:sandbox, :allowed_tools], [operation_id]),
      upstream: %{protocol: :app_server},
      consumer_surface: %{
        mode: :common,
        normalized_id: operation_id,
        action_name: action_name(operation_id)
      },
      schema_policy: %{
        input: :defined,
        output: :defined
      },
      jido: %{action: %{name: action_name(operation_id)}},
      metadata:
        metadata
        |> Map.put(:runtime_family, @runtime_family)
    })
  end

  defp action_name(operation_id) do
    operation_id
    |> String.replace(".", "_")
  end

  defp turn_input_schema do
    Zoi.object(%{
      prompt: Zoi.string(),
      host_tools: Zoi.list(host_tool_schema()) |> Zoi.default([]),
      continuation: any_map_schema() |> Zoi.nullish() |> Zoi.optional(),
      provider_metadata: any_map_schema() |> Zoi.default(%{})
    })
  end

  defp host_tool_schema do
    Zoi.object(%{
      name: Zoi.string(),
      description: Zoi.string() |> Zoi.optional(),
      inputSchema: any_map_schema(),
      outputSchema: any_map_schema() |> Zoi.optional()
    })
  end

  defp any_map_schema do
    Zoi.map(Zoi.any(), Zoi.any(), [])
  end

  defp turn_output_schema do
    Zoi.object(%{
      text: Zoi.string(),
      provider_session_id: Zoi.string(),
      status: Zoi.atom(),
      auth_binding: Zoi.string(),
      events: Zoi.list(Zoi.any()) |> Zoi.default([])
    })
  end

  defp status_output_schema do
    Zoi.object(%{
      status: Zoi.atom(),
      provider_session_id: Zoi.string() |> Zoi.nullish() |> Zoi.optional(),
      auth_binding: Zoi.string(),
      message: Zoi.string() |> Zoi.nullish() |> Zoi.optional()
    })
  end
end
