defmodule Jido.Integration.InferenceRuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.InferenceRuntime
  alias Jido.Integration.InferenceRuntime.{FakeInvoker, RuntimeDeps}
  alias Jido.Integration.ModelInvocation.Receipt

  @hash "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  test "fake invoker emits a deterministic completion receipt" do
    assert {:ok, %{receipt: %Receipt{} = receipt, stream_fragments: []}} =
             InferenceRuntime.invoke(request_attrs(), invoker: FakeInvoker)

    assert receipt.status == :ok
    assert receipt.provider_ref == "openai"
    assert receipt.context_packet_ref == "context-packet://tenant-1/packet-1"
    assert receipt.route_decision_ref == "route-decision://tenant-1/route-1"
    assert receipt.token_summary["source"] == "deterministic_fixture"
  end

  test "fake invoker emits streaming receipt fragments" do
    assert {:ok, %{receipt: receipt, stream_fragments: [fragment]}} =
             InferenceRuntime.invoke(request_attrs(stream?: true, operation: :stream_text),
               invoker: FakeInvoker
             )

    assert [fragment.fragment_ref] == receipt.stream_refs
    assert fragment.chunk_hash =~ "sha256:"
    assert fragment.metadata["payload_mode"] == "artifact_ref"
  end

  test "runtime rejects missing credential lease before invocation" do
    assert {:error, %ArgumentError{} = error} =
             request_attrs()
             |> Map.delete(:credential_lease_ref)
             |> InferenceRuntime.invoke(invoker: FakeInvoker)

    assert Exception.message(error) =~ "credential_lease_ref is required"
  end

  test "runtime rejects raw prompt metadata before invocation" do
    assert {:error, %ArgumentError{} = error} =
             InferenceRuntime.invoke(request_attrs(metadata: %{"prompt" => "raw"}),
               invoker: FakeInvoker
             )

    assert Exception.message(error) =~ "not allowed"
  end

  test "runtime dependencies are explicit and never selected from ambient provider state" do
    assert {:ok, %RuntimeDeps{invoker: FakeInvoker}} = RuntimeDeps.new([])

    assert {:error, %ArgumentError{} = error} =
             request_attrs()
             |> Map.delete(:provider_ref)
             |> InferenceRuntime.invoke([])

    assert Exception.message(error) =~ "provider_ref is required"
  end

  defp request_attrs(overrides \\ []) do
    Map.merge(
      %{
        invocation_ref: "model-invocation://tenant-1/run-1",
        tenant_ref: "tenant://1",
        workflow_ref: "workflow://tenant-1/run-1",
        context_packet_ref: "context-packet://tenant-1/packet-1",
        route_decision_ref: "route-decision://tenant-1/route-1",
        prompt_artifact_ref: "artifact://prompt/1",
        provider_payload_ref: "artifact://provider-payload/1",
        payload_hash: @hash,
        model_profile_ref: "model-profile://openai/gpt-4.1-mini",
        provider_ref: "openai",
        endpoint_ref: "endpoint://openai/chat",
        runtime_ref: "runtime://req-llm/client",
        runtime_kind: :client,
        credential_lease_ref: "credential-lease://tenant-1/openai",
        trace_ref: "trace://run-1",
        idempotency_key: "idem-1",
        redaction_class: "bounded_receipt",
        payload_mode: "artifact_ref",
        metadata: %{"safe" => "yes"}
      },
      Map.new(overrides)
    )
  end
end
