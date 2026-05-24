defmodule Jido.Integration.InferenceRuntime.FakeInvoker do
  @moduledoc """
  Deterministic provider-free invoker for tests and local StackLab proofs.
  """

  @behaviour Jido.Integration.InferenceRuntime.Invoker

  alias Jido.Integration.ModelInvocation.{Canonical, Receipt, Request, StreamFragment}

  @impl true
  def invoke(%Request{} = request, _opts) do
    output_artifact_ref =
      Canonical.artifact_ref("artifact://jido/fake-model-output", dump(request))

    fragments =
      if request.stream? do
        [stream_fragment(request, 0)]
      else
        []
      end

    with {:ok, receipt} <-
           Receipt.from_request(request, %{
             status: :ok,
             token_summary: token_summary(request),
             cost_summary: %{"estimated_usd" => 0.0, "currency" => "USD"},
             output_artifact_ref: output_artifact_ref,
             stream_refs: Enum.map(fragments, & &1.fragment_ref),
             metadata: %{
               "backend" => "fake",
               "deterministic?" => true,
               "request_hash" => Request.canonical_hash(request)
             }
           }) do
      {:ok, %{receipt: receipt, stream_fragments: fragments}}
    end
  end

  defp stream_fragment(%Request{} = request, sequence) do
    chunk_hash =
      Canonical.checksum!(%{"request" => Request.dump(request), "sequence" => sequence})

    StreamFragment.new!(%{
      invocation_ref: request.invocation_ref,
      tenant_ref: request.tenant_ref,
      stream_ref: "stream://jido/fake/#{URI.encode_www_form(request.invocation_ref)}",
      sequence: sequence,
      chunk_ref:
        Canonical.artifact_ref("artifact://jido/fake-stream-chunk", %{
          "invocation_ref" => request.invocation_ref,
          "sequence" => sequence
        }),
      chunk_hash: chunk_hash,
      byte_count: 0,
      token_count: 0,
      trace_ref: request.trace_ref,
      redaction_class: request.redaction_class,
      metadata: %{"backend" => "fake", "payload_mode" => request.payload_mode}
    })
  end

  defp token_summary(%Request{} = request) do
    base =
      request
      |> dump()
      |> Canonical.checksum!()
      |> String.slice(-4, 4)
      |> String.to_integer(16)

    input = rem(base, 97) + 1
    output = rem(base, 31)

    %{
      "input" => input,
      "output" => output,
      "total" => input + output,
      "source" => "deterministic_fixture"
    }
  end

  defp dump(%Request{} = request), do: Request.dump(request)
end
