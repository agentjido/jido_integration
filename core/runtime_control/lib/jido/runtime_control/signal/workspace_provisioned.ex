defmodule Jido.RuntimeControl.Signal.WorkspaceProvisioned do
  @moduledoc """
  Signal emitted when a runtime-control workspace is successfully provisioned.
  """

  use Jido.Signal,
    type: "jido.runtime_control.workspace.provisioned",
    default_source: "/jido/runtime_control/workspace",
    schema: [
      run_id: [type: :string, required: false],
      request_id: [type: :string, required: false],
      workspace_id: [type: :string, required: false],
      session_id: [type: :string, required: false],
      provider: [type: :atom, required: false]
    ]
end
