defmodule Jido.Integration.V2.Connectors.GitHub.Actions.UpdateComment do
  @moduledoc false

  use Jido.Action,
    name: "github_comment_update",
    description: "Updates a deterministic GitHub issue comment",
    schema: [
      repo: [type: :string, required: true],
      comment_id: [type: :integer, required: true],
      body: [type: :string, required: true]
    ]

  alias Jido.Integration.V2.Connectors.GitHub.ActionSupport

  @impl true
  def run(params, context), do: ActionSupport.run(:comment_update, params, context)
end
