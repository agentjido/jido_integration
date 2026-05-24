defmodule Jido.Integration.InferenceRuntime.ControlPlaneInvoker do
  @moduledoc """
  Explicit invoker that delegates to the existing Jido control-plane inference path.
  """

  @behaviour Jido.Integration.InferenceRuntime.Invoker

  alias Jido.Integration.ModelInvocation.{Receipt, Request}
  alias Jido.Integration.V2.ControlPlane

  @impl true
  def invoke(%Request{} = request, opts) do
    with {:ok, control_plane_result} <-
           request
           |> Request.to_inference_request()
           |> ControlPlane.invoke_inference(control_plane_opts(request, opts)),
         {:ok, receipt} <- receipt_from_control_plane(request, control_plane_result) do
      {:ok, Map.put(control_plane_result, :receipt, receipt)}
    end
  end

  defp control_plane_opts(%Request{} = request, opts) do
    opts
    |> Keyword.drop([:invoker])
    |> Keyword.put_new(:require_artifact_refs?, true)
    |> Keyword.put_new(:trace_id, request.trace_ref)
    |> Keyword.put_new(:decision_ref, request.route_decision_ref)
    |> Keyword.put_new(:context_metadata, %{tenant_id: request.tenant_ref})
  end

  defp receipt_from_control_plane(%Request{} = request, result) do
    inference_result = Map.fetch!(result, :inference_result)

    Receipt.from_request(request, %{
      status: inference_result.status,
      token_summary: token_summary(inference_result),
      cost_summary: cost_summary(result),
      output_artifact_ref: output_artifact_ref(result),
      stream_refs: stream_refs(result),
      failure: inference_result.error,
      metadata: %{
        "backend" => "control_plane",
        "run_id" => result.run.run_id,
        "attempt_id" => result.attempt.attempt_id,
        "endpoint_id" => inference_result.endpoint_id
      }
    })
  end

  defp token_summary(inference_result) do
    inference_result.usage || %{"source" => "provider_unreported"}
  end

  defp cost_summary(result) do
    result.response_summary
    |> case do
      %{} = summary -> Map.get(summary, :cost, Map.get(summary, "cost", %{}))
      _ -> %{}
    end
    |> Map.put_new("source", "control_plane")
  end

  defp output_artifact_ref(result) do
    result.attempt.output_payload_ref || result.run.result_payload_ref
  end

  defp stream_refs(%{stream: nil}), do: []

  defp stream_refs(%{stream: stream}) do
    stream
    |> Map.get(:checkpoints, [])
    |> Enum.map(&Map.get(&1, :stream_id))
    |> Enum.reject(&is_nil/1)
  end
end
