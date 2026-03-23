defmodule Jido.Integration.V2.Connectors.CodexCli do
  @moduledoc """
  Example external session connector package.

  This connector publishes the canonical session-family authored shape on the
  shared common consumer-surface spine through the `Jido.Harness` `asm`
  driver.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Connectors.CodexCli.Handler
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
          handler: Handler,
          input_schema:
            Zoi.object(%{
              prompt: Zoi.string()
            }),
          output_schema:
            Zoi.object(%{
              reply: Zoi.string(),
              turn: Zoi.integer(),
              workspace: Zoi.string(),
              auth_binding: Zoi.string(),
              approval_mode: Zoi.atom()
            }),
          permissions: %{required_scopes: ["session:execute"]},
          runtime: %{
            driver: "asm",
            provider: :codex,
            options: %{}
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
          consumer_surface: %{
            mode: :common,
            normalized_id: "codex.exec.session",
            action_name: "codex_exec_session"
          },
          schema_policy: %{
            input: :defined,
            output: :defined
          },
          jido: %{action: %{name: "codex_exec_session"}},
          metadata: %{
            runtime_family: %{
              session_affinity: :connection,
              resumable: true,
              approval_required: true,
              stream_capable: true,
              lifecycle_owner: :asm,
              runtime_ref: :session
            }
          }
        })
      ],
      triggers: [],
      runtime_families: [:session]
    })
  end
end
