defmodule Jido.Integration.V2.ControlPlane.AgentRuntimeReceiptAdapter do
  @moduledoc """
  Converts control-plane runtime results into generic agent runtime receipts.
  """

  alias Jido.Integration.AgentInterop.Receipt, as: AgentRuntimeReceipt
  alias Jido.Integration.V2.RuntimeResult

  @default_runtime_family :interop

  @spec from_runtime_result(RuntimeResult.t(), map()) ::
          {:ok, AgentRuntimeReceipt.t()} | {:error, Exception.t()}
  def from_runtime_result(%RuntimeResult{} = runtime_result, context) when is_map(context) do
    AgentRuntimeReceipt.new(receipt_attrs(runtime_result, context))
  end

  @spec from_runtime_result!(RuntimeResult.t(), map()) :: AgentRuntimeReceipt.t()
  def from_runtime_result!(%RuntimeResult{} = runtime_result, context) when is_map(context) do
    AgentRuntimeReceipt.new!(receipt_attrs(runtime_result, context))
  end

  defp receipt_attrs(%RuntimeResult{} = runtime_result, context) do
    output = runtime_result.output || %{}

    %{
      receipt_ref: required_context(context, :receipt_ref),
      ledger_ref: required_context(context, :ledger_ref),
      lower_invocation_ref:
        context_value(context, :lower_invocation_ref) ||
          output_value(output, :lower_request_ref) ||
          required_context(context, :invocation_ref),
      runtime_family: context_value(context, :runtime_family) || @default_runtime_family,
      capability_ref:
        context_value(context, :capability_ref) ||
          output_value(output, :capability_id) ||
          required_context(context, :capability_id),
      authority_ref: required_context(context, :authority_ref),
      idempotency_key: required_context(context, :idempotency_key),
      status: context_value(context, :status) || infer_status(runtime_result),
      output_summary: output_summary(runtime_result),
      output_ref: context_value(context, :output_ref),
      event_seq_hint: context_value(context, :event_seq_hint),
      evidence_refs: context_value(context, :evidence_refs) || [],
      trace_ref: context_value(context, :trace_ref),
      started_at: context_value(context, :started_at),
      completed_at: context_value(context, :completed_at),
      metadata: %{
        "source" => "control_plane",
        "runtime_ref_id" => runtime_result.runtime_ref_id
      }
    }
  end

  defp output_summary(%RuntimeResult{} = runtime_result) do
    output = runtime_result.output || %{}

    %{
      "runtime_ref_id" => runtime_result.runtime_ref_id,
      "event_count" => length(runtime_result.events),
      "artifact_count" => length(runtime_result.artifacts),
      "adapter" => output_value(output, :adapter),
      "lower_runtime_kind" => output_value(output, :lower_runtime_kind)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp infer_status(%RuntimeResult{output: output}) do
    case output_value(output || %{}, :error) do
      nil -> :succeeded
      _error -> :failed
    end
  end

  defp required_context(context, field) do
    context_value(context, field) ||
      raise ArgumentError, "agent runtime receipt context requires #{field}"
  end

  defp context_value(context, field) do
    Map.get(context, field) || Map.get(context, Atom.to_string(field))
  end

  defp output_value(output, field) when is_map(output) do
    Map.get(output, field) || Map.get(output, Atom.to_string(field))
  end
end
