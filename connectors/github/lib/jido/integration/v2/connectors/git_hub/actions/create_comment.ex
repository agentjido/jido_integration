defmodule Jido.Integration.V2.Connectors.GitHub.Actions.CreateComment do
  @moduledoc false

  use Jido.Action,
    name: "github_comment_create",
    description: "Creates a deterministic GitHub issue comment",
    schema: [
      repo: [type: :string, required: true],
      issue_number: [type: :integer, required: true],
      body: [type: :string, required: true]
    ]

  alias Jido.Integration.V2.Connectors.GitHub.ActionSupport

  @impl true
  def run(params, context), do: ActionSupport.run(:comment_create, params, context)
end
