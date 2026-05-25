defmodule JidoIntegration.Bridges.ExecutionPlaneBridge.Transport.Fixture do
  @moduledoc """
  Deterministic Jido-to-Execution Plane transport for tests.
  """

  @behaviour JidoIntegration.Bridges.ExecutionPlaneBridge.Transport

  @impl true
  def execute_lane(request, opts) when is_map(request) and is_list(opts) do
    opts
    |> configured_response()
    |> case do
      nil ->
        {:ok,
         %{
           "status" => "completed",
           "lower_receipt_ref" =>
             Map.get(request, "idempotency_key", "lower://fixture/execution-plane"),
           "correlation_ref" =>
             Map.get(request, "correlation_ref", "correlation://fixture/execution-plane")
         }}

      fun when is_function(fun, 2) ->
        fun.(request, opts)

      fun when is_function(fun, 1) ->
        fun.(request)

      result ->
        result
    end
    |> normalize_result()
  end

  defp configured_response(opts) do
    responses = Keyword.get(opts, :responses, %{})

    Keyword.get(opts, :execute_lane) || Map.get(responses, :execute_lane) ||
      Map.get(responses, "execute_lane")
  end

  defp normalize_result({:ok, result}) when is_map(result), do: {:ok, result}
  defp normalize_result({:error, reason}) when is_map(reason), do: {:error, reason}
  defp normalize_result(result) when is_map(result), do: {:ok, result}

  defp normalize_result(reason),
    do: {:error, error(:invalid_fixture_response, %{"reason" => inspect(reason)})}

  defp error(code, attrs),
    do: Map.merge(%{"code" => Atom.to_string(code), "transport" => "fixture"}, attrs)
end
