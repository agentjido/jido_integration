defmodule Jido.RuntimeControl.Actions.ValidateProviderRuntime do
  @moduledoc "Validate provider-specific runtime prerequisites in an existing shell session."

  use Jido.Action,
    name: "runtime_control_validate_provider_runtime",
    description: "Validate provider runtime requirements",
    schema: [
      provider: [type: :atom, required: true],
      session_id: [type: :string, required: true],
      opts: [type: :map, default: %{}]
    ]

  alias Jido.RuntimeControl.Actions.Helpers
  alias Jido.RuntimeControl.Exec.ProviderRuntime

  @impl true
  def run(params, _context) do
    Helpers.with_keyword_opts(params.opts, "Unsupported option key for provider runtime validation", fn opts ->
      ProviderRuntime.validate_provider_runtime(
        params.provider,
        params.session_id,
        opts
      )
    end)
  end
end
