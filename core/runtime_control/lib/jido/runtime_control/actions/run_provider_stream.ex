defmodule Jido.RuntimeControl.Actions.RunProviderStream do
  @moduledoc "Run a provider command in stream-json mode and summarize runtime output."

  use Jido.Action,
    name: "runtime_control_run_provider_stream",
    description: "Run provider stream command",
    schema: [
      provider: [type: :atom, required: true],
      session_id: [type: :string, required: true],
      cwd: [type: :string, required: true],
      command_or_opts: [type: :any, required: true]
    ]

  alias Jido.RuntimeControl.Exec.Stream

  @impl true
  def run(params, _context) do
    Stream.run_stream(
      params.provider,
      params.session_id,
      params.cwd,
      params.command_or_opts
    )
  end
end
