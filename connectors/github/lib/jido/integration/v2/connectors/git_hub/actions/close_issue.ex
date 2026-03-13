defmodule Jido.Integration.V2.Connectors.GitHub.Actions.CloseIssue do
  @moduledoc false

  use Jido.Action,
    name: "github_issue_close",
    description: "Closes a deterministic GitHub issue",
    schema: [
      repo: [type: :string, required: true],
      issue_number: [type: :integer, required: true]
    ]

  alias Jido.Integration.V2.Connectors.GitHub.ActionSupport

  @impl true
  def run(params, context), do: ActionSupport.run(:issue_close, params, context)
end
