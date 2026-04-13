defmodule Jido.Integration.V2.Connectors.GitHub.FixtureTransport do
  @moduledoc false

  alias Jido.Integration.V2.Connectors.GitHub.Fixtures

  def send(request, context) do
    transport_opts = Map.get(context, :transport_opts, [])

    if test_pid = Keyword.get(transport_opts, :test_pid) do
      Kernel.send(test_pid, {:transport_request, request, context})
    end

    case Keyword.fetch(transport_opts, :response) do
      {:ok, nil} ->
        Fixtures.response_for_request(request, context)

      {:ok, response} when is_function(response, 2) ->
        response.(request, context)

      {:ok, response} ->
        response

      :error ->
        Fixtures.response_for_request(request, context)
    end
  end
end
