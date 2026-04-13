defmodule Jido.RuntimeControl.Signal.ProviderBootstrapped do
  @moduledoc """
  Signal emitted when provider bootstrap steps complete.
  """

  use Jido.Signal,
    type: "jido.runtime_control.provider.bootstrapped",
    default_source: "/jido/runtime_control/provider",
    schema: [
      run_id: [type: :string, required: false],
      request_id: [type: :string, required: false],
      session_id: [type: :string, required: false],
      provider: [type: :atom, required: false],
      bootstrap: [type: :map, required: false]
    ]
end
