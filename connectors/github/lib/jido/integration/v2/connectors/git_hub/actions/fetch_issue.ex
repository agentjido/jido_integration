defmodule Jido.Integration.V2.Connectors.GitHub.Actions.FetchIssue do
  @moduledoc false

  use Jido.Action,
    name: "github_issue_fetch",
    description: "Fetches a deterministic GitHub issue by number",
    schema: [
      repo: [type: :string, required: true],
      issue_number: [type: :integer, required: true]
    ]

  alias Jido.Integration.V2.Connectors.GitHub.ActionSupport

  @impl true
  def run(params, context), do: ActionSupport.run(:issue_fetch, params, context)
end
