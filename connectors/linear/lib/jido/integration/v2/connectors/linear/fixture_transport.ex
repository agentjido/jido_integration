defmodule Jido.Integration.V2.Connectors.Linear.FixtureTransport do
  @moduledoc false

  @behaviour Prismatic.Transport

  alias Jido.Integration.V2.Connectors.Linear.Fixtures

  @impl true
  def execute(context, payload, opts) do
    if test_pid = Keyword.get(opts, :test_pid) do
      Kernel.send(test_pid, {:transport_request, payload, context, opts})
    end

    case Keyword.fetch(opts, :response) do
      {:ok, nil} ->
        Fixtures.response_for_request(payload, context, opts)

      {:ok, response} when is_function(response, 3) ->
        response.(payload, context, opts)

      {:ok, response} ->
        response

      :error ->
        Fixtures.response_for_request(payload, context, opts)
    end
  end
end
