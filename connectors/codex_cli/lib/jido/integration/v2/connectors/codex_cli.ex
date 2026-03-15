defmodule Jido.Integration.V2.Connectors.CodexCli do
  @moduledoc """
  Example session connector package.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Connectors.CodexCli.Provider
  alias Jido.Integration.V2.Manifest

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: "codex_cli",
      capabilities: [
        Capability.new!(%{
          id: "codex.exec.session",
          connector: "codex_cli",
          runtime_class: :session,
          kind: :session_operation,
          transport_profile: :stdio,
          handler: Provider,
          metadata: %{
            required_scopes: ["session:execute"],
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
            }
          }
        })
      ]
    })
  end
end
