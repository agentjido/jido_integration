defmodule Jido.Integration.V2.Connectors.GitHub.Actions.UpdateIssue do
  @moduledoc false

  use Jido.Action,
    name: "github_issue_update",
    description: "Updates a deterministic GitHub issue",
    schema: [
      repo: [type: :string, required: true],
      issue_number: [type: :integer, required: true],
      title: [type: :string, required: false],
      body: [type: :string, required: false],
      state: [type: :string, required: false],
      labels: [type: {:list, :string}, required: false],
      assignees: [type: {:list, :string}, required: false]
    ]

  alias Jido.Integration.V2.Connectors.GitHub.ActionSupport

  @impl true
  def run(params, context), do: ActionSupport.run(:issue_update, params, context)
end
