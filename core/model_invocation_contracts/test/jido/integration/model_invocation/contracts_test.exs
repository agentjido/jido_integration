defmodule Jido.Integration.ModelInvocation.ContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.ModelInvocation.{Receipt, Request, StreamFragment}
  alias Jido.Integration.V2.InferenceRequest

  @hash "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  test "request round-trips as a ref-only inference request" do
    request = Request.new!(request_attrs())

    dump = Request.dump(request)
    inference_request = Request.to_inference_request(request)

    assert dump["prompt_artifact_ref"] == "artifact://prompt/1"
    assert dump["provider_payload_ref"] == "artifact://provider-payload/1"
    assert Request.new!(dump) == request
    assert %InferenceRequest{} = inference_request
    assert inference_request.messages == []
    assert inference_request.prompt == nil
    assert inference_request.metadata["workflow_ref"] == "workflow://tenant-1/run-1"
    assert inference_request.metadata["payload_hash"] == @hash
  end

  test "fixture request may omit credential lease ref" do
    assert {:ok, request} =
             request_attrs(runtime_kind: :fixture, credential_lease_ref: nil)
             |> Request.new()

    assert request.credential_lease_ref == nil
  end

  test "non-fixture request fails closed when credential lease ref is missing" do
    assert {:error, %ArgumentError{} = error} =
             request_attrs(runtime_kind: :client)
             |> Map.delete(:credential_lease_ref)
             |> Request.new()

    assert Exception.message(error) =~ "credential_lease_ref is required for non-fixture runtimes"
  end

  test "request rejects raw provider and prompt payload fields" do
    assert {:error, %ArgumentError{} = error} =
             request_attrs(metadata: %{"provider_payload" => %{"body" => "raw"}})
             |> Request.new()

    assert Exception.message(error) =~ "not allowed"
  end

  test "request rejects forbidden top-level payload and credential fields" do
    for key <- [:raw_prompt, :provider_payload, :messages, :token, :authorization, "raw_body"] do
      assert {:error, %ArgumentError{} = error} =
               request_attrs()
               |> Map.put(key, "secret-ish")
               |> Request.new()

      assert Exception.message(error) =~ "not allowed"
    end
  end

  test "receipt carries token and cost facts without raw output" do
    request = Request.new!(request_attrs())

    receipt =
      Receipt.new!(%{
        invocation_ref: request.invocation_ref,
        tenant_ref: request.tenant_ref,
        status: :ok,
        workflow_ref: request.workflow_ref,
        context_packet_ref: request.context_packet_ref,
        route_decision_ref: request.route_decision_ref,
        prompt_artifact_ref: request.prompt_artifact_ref,
        provider_payload_ref: request.provider_payload_ref,
        payload_hash: request.payload_hash,
        model_profile_ref: request.model_profile_ref,
        provider_ref: request.provider_ref,
        endpoint_ref: request.endpoint_ref,
        runtime_ref: request.runtime_ref,
        runtime_kind: request.runtime_kind,
        credential_lease_ref: request.credential_lease_ref,
        trace_ref: request.trace_ref,
        idempotency_key: request.idempotency_key,
        token_summary: %{"input" => 4, "output" => 2, "total" => 6},
        cost_summary: %{"estimated_usd" => 0.0},
        redaction_class: request.redaction_class,
        payload_mode: request.payload_mode,
        output_artifact_ref: "artifact://model-output/1"
      })

    assert receipt.receipt_ref =~ "jido-model-invocation-receipt/sha256:"
    assert Receipt.dump(receipt)["token_summary"]["total"] == 6
  end

  test "stream fragments carry hashes and refs, not chunk text" do
    fragment =
      StreamFragment.new!(%{
        invocation_ref: "model-invocation://tenant-1/run-1",
        tenant_ref: "tenant://1",
        stream_ref: "stream://tenant-1/invocation-1",
        sequence: 0,
        chunk_ref: "artifact://chunk/0",
        chunk_hash: @hash,
        byte_count: 42,
        token_count: 3,
        trace_ref: "trace://run-1",
        redaction_class: "bounded_receipt"
      })

    assert fragment.fragment_ref =~ "jido-model-invocation-stream-fragment/sha256:"
    assert StreamFragment.dump(fragment)["chunk_hash"] == @hash
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
        token_budget_ref: "budget://tokens/1",
        cost_budget_ref: "budget://cost/1",
        redaction_class: "bounded_receipt",
        payload_mode: "artifact_ref",
        metadata: %{"safe" => "yes"}
      },
      Map.new(overrides)
    )
  end
end
