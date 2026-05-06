defmodule Jido.ModelProviderRegistry.CapabilityMatrixTest do
  use ExUnit.Case, async: true

  alias Jido.ModelProviderRegistry.CapabilityMatrix

  test "distinguishes every required model capability" do
    capabilities = CapabilityMatrix.capabilities()

    for capability <- [
          :chat,
          :completion,
          :embeddings,
          :rerank,
          :tool_calls,
          :vision,
          :audio,
          :structured_json,
          :streaming,
          :context_length,
          :local_endpoint,
          :cost_profile
        ] do
      assert capability in capabilities
    end
  end

  test "unknown capabilities fail closed before provider effects" do
    assert {:ok, normalized} = CapabilityMatrix.validate([:chat, "streaming"])
    assert normalized == [:chat, :streaming]

    assert {:error, {:unknown_capabilities, [:unknown]}} =
             CapabilityMatrix.validate([:chat, :unknown])
  end
end
