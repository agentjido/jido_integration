defmodule Jido.RuntimeControl.Actions.ProvisionWorkspace do
  @moduledoc "Provision a workspace/session for runtime-control execution."

  use Jido.Action,
    name: "runtime_control_provision_workspace",
    description: "Provision runtime-control workspace",
    schema: [
      workspace_id: [type: :string, required: true],
      opts: [type: :map, default: %{}]
    ]

  alias Jido.RuntimeControl.Actions.Helpers
  alias Jido.RuntimeControl.Exec.Workspace

  @impl true
  def run(params, _context) do
    Helpers.with_keyword_opts(params.opts, "Unsupported option key for provision workspace", fn opts ->
      Workspace.provision_workspace(params.workspace_id, opts)
    end)
  end
end
