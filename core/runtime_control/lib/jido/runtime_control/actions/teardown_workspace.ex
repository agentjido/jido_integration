defmodule Jido.RuntimeControl.Actions.TeardownWorkspace do
  @moduledoc "Tear down a workspace/session for runtime-control execution."

  use Jido.Action,
    name: "runtime_control_teardown_workspace",
    description: "Teardown runtime-control workspace",
    schema: [
      session_id: [type: :string, required: true],
      opts: [type: :map, default: %{}]
    ]

  alias Jido.RuntimeControl.Actions.Helpers
  alias Jido.RuntimeControl.Exec.Workspace

  @impl true
  def run(params, _context) do
    Helpers.with_keyword_opts(params.opts, "Unsupported option key for workspace teardown", fn opts ->
      {:ok, Workspace.teardown_workspace(params.session_id, opts)}
    end)
  end
end
