defmodule Jido.Integration.V2.Connectors.GitHub.Actions.ListIssues do
  @moduledoc false

  use Jido.Action,
    name: "github_issue_list",
    description: "Lists deterministic GitHub issues for a repository",
    schema: [
      repo: [type: :string, required: true],
      state: [type: :string, required: false],
      per_page: [type: :integer, required: false],
      page: [type: :integer, required: false]
    ]

  alias Jido.Integration.V2.Connectors.GitHub.ActionSupport

  @impl true
  def run(params, context), do: ActionSupport.run(:issue_list, params, context)
end
