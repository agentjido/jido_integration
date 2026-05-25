defmodule JidoIntegration.RemoteFacade.ModelRuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.ModelInvocation.Canonical
  alias JidoIntegration.RemoteFacade.ModelRuntime

  test "declares owner-defined model runtime group" do
    assert ModelRuntime.owner_group() == {ModelRuntime, :model_runtime}
  end

  test "submits model invocation and returns accepted-ref plus receipt" do
    assert {:ok, result} = ModelRuntime.submit_invocation(valid_request())

    assert result["status"] == "accepted"
    assert result["accepted_ref"] == "invocation://one"
    assert result["receipt"]["invocation_ref"] == "invocation://one"
    assert result["async_contract"] == "accepted_ref_plus_readback"
  end

  test "rejects invalid invocation envelope" do
    assert {:error, %{"code" => "model_invocation_failed", "reason" => reason}} =
             valid_request()
             |> Map.delete("tenant_ref")
             |> ModelRuntime.submit_invocation()

    assert String.contains?(reason, "tenant_ref")
  end

  test "readback returns bounded invocation facts" do
    assert {:ok, readback} = ModelRuntime.read_invocation("invocation://one")

    assert readback["invocation_ref"] == "invocation://one"
    assert readback["owner"] == "jido_integration"
  end

  defp valid_request do
    %{
      "invocation_ref" => "invocation://one",
      "tenant_ref" => "tenant://one",
      "context_packet_ref" => "context-packet://one",
      "route_decision_ref" => "route-decision://one",
      "prompt_artifact_ref" => "prompt-artifact://one",
      "provider_payload_ref" => "provider-payload://one",
      "payload_hash" => Canonical.checksum!(%{"payload" => "one"}),
      "model_profile_ref" => "model-profile://fake",
      "provider_ref" => "provider://fake",
      "endpoint_ref" => "endpoint://fake",
      "runtime_ref" => "runtime://fake",
      "runtime_kind" => "fixture",
      "credential_lease_ref" => "credential-lease://fake",
      "trace_ref" => "trace://one",
      "idempotency_key" => "idem://one",
      "redaction_class" => "tenant_sensitive",
      "payload_mode" => "refs_only"
    }
  end
end
