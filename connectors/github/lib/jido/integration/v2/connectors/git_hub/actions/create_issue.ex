defmodule Jido.Integration.V2.Connectors.GitHub.Actions.CreateIssue do
  @moduledoc false

  use Jido.Action,
    name: "github_issue_create",
    description: "Creates a deterministic GitHub issue",
    schema: [
      repo: [type: :string, required: true],
      title: [type: :string, required: true],
      body: [type: :string, required: false],
      labels: [type: {:list, :string}, required: false],
      assignees: [type: {:list, :string}, required: false]
    ]

  alias Jido.Integration.V2.Connectors.GitHub.ActionSupport

  @impl true
  def run(params, context), do: ActionSupport.run(:issue_create, params, context)
end
