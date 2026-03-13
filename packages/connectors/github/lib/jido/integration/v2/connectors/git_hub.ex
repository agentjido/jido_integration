defmodule Jido.Integration.V2.Connectors.GitHub do
  @moduledoc """
  Example direct connector package.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Connectors.GitHub.Actions.CreateIssue
  alias Jido.Integration.V2.Manifest

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: "github",
      capabilities: [
        Capability.new!(%{
          id: "github.issue.create",
          connector: "github",
          runtime_class: :direct,
          kind: :operation,
          transport_profile: :action,
          handler: CreateIssue,
          metadata: %{
            required_scopes: ["repo"],
            policy: %{
              environment: %{allowed: [:prod, :staging]},
              sandbox: %{
                level: :standard,
                egress: :restricted,
                approvals: :auto,
                allowed_tools: ["github.api.issue.create"]
              }
            }
          }
        })
      ]
    })
  end
end
