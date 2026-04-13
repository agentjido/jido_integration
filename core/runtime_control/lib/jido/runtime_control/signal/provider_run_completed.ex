defmodule Jido.RuntimeControl.Signal.ProviderRunCompleted do
  @moduledoc """
  Signal emitted when provider stream execution completes successfully.
  """

  use Jido.Signal,
    type: "jido.runtime_control.provider.run.completed",
    default_source: "/jido/runtime_control/provider",
    schema: [
      run_id: [type: :string, required: false],
      request_id: [type: :string, required: false],
      session_id: [type: :string, required: false],
      provider: [type: :atom, required: false],
      success: [type: :boolean, required: false],
      event_count: [type: :integer, required: false],
      result_text: [type: :string, required: false]
    ]
end
