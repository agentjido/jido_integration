defmodule Jido.Integration.V2.Connectors.CodexCli do
  @moduledoc """
  Example session connector package.

  It keeps the legacy `integration_session_bridge` path alive as a migration
  fixture while the control plane moves new external runtimes onto the
  integration-owned ASM bridge.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Connectors.CodexCli.Provider
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec

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
          requested_scopes: ["session:execute"],
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
        OperationSpec.new!(%{
          operation_id: "codex.exec.session",
          name: "exec_session",
          display_name: "Execute session",
          description: "Runs an interactive codex session turn",
          runtime_class: :session,
          transport_mode: :stdio,
          handler: Provider,
          input_schema: Zoi.map(description: "Session input"),
          output_schema: Zoi.map(description: "Session output"),
          permissions: %{required_scopes: ["session:execute"]},
          runtime: %{
            driver: "integration_session_bridge"
          },
          policy: %{
            environment: %{allowed: [:prod]},
            sandbox: %{
              level: :strict,
              egress: :restricted,
              approvals: :manual,
              file_scope: "/workspaces/codex_cli",
              allowed_tools: ["codex.exec.session"]
            }
          },
          upstream: %{protocol: :stdio},
          jido: %{action: %{name: "codex_exec_session"}}
        })
      ],
      triggers: [],
      runtime_families: [:session]
    })
  end
end
