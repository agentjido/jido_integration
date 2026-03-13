defmodule Jido.Integration.V2.Connectors.GitHub do
  @moduledoc """
  Deterministic direct GitHub connector package.
  """

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Connectors.GitHub.Actions.CloseIssue
  alias Jido.Integration.V2.Connectors.GitHub.Actions.CreateComment
  alias Jido.Integration.V2.Connectors.GitHub.Actions.CreateIssue
  alias Jido.Integration.V2.Connectors.GitHub.Actions.FetchIssue
  alias Jido.Integration.V2.Connectors.GitHub.Actions.LabelIssue
  alias Jido.Integration.V2.Connectors.GitHub.Actions.ListIssues
  alias Jido.Integration.V2.Connectors.GitHub.Actions.UpdateComment
  alias Jido.Integration.V2.Connectors.GitHub.Actions.UpdateIssue
  alias Jido.Integration.V2.Manifest

  @environment_allowed [:prod, :staging]
  @policy_defaults %{
    environment: %{allowed: @environment_allowed},
    sandbox: %{
      level: :standard,
      egress: :restricted,
      approvals: :auto
    }
  }

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: "github",
      capabilities: [
        capability("github.comment.create", CreateComment, ["github.api.comment.create"]),
        capability("github.comment.update", UpdateComment, ["github.api.comment.update"]),
        capability("github.issue.close", CloseIssue, ["github.api.issue.close"]),
        capability("github.issue.create", CreateIssue, ["github.api.issue.create"]),
        capability("github.issue.fetch", FetchIssue, ["github.api.issue.fetch"]),
        capability("github.issue.label", LabelIssue, ["github.api.issue.label"]),
        capability("github.issue.list", ListIssues, ["github.api.issue.list"]),
        capability("github.issue.update", UpdateIssue, ["github.api.issue.update"])
      ]
    })
  end

  defp capability(id, handler, allowed_tools) do
    Capability.new!(%{
      id: id,
      connector: "github",
      runtime_class: :direct,
      kind: :operation,
      transport_profile: :action,
      handler: handler,
      metadata: %{
        required_scopes: ["repo"],
        policy: put_in(@policy_defaults, [:sandbox, :allowed_tools], allowed_tools)
      }
    })
  end
end
