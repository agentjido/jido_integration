defmodule Jido.Integration.V2.Connectors.GitHub.Actions.LabelIssue do
  @moduledoc false

  use Jido.Action,
    name: "github_issue_label",
    description: "Adds labels to a deterministic GitHub issue",
    schema: [
      repo: [type: :string, required: true],
      issue_number: [type: :integer, required: true],
      labels: [type: {:list, :string}, required: true]
    ]

  alias Jido.Integration.V2.Connectors.GitHub.ActionSupport

  @impl true
  def run(params, context), do: ActionSupport.run(:issue_label, params, context)
end
