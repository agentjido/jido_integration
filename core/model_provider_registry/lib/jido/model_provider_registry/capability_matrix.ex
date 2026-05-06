defmodule Jido.ModelProviderRegistry.CapabilityMatrix do
  @moduledoc """
  Bounded capability matrix for governed model profiles.
  """

  @capabilities [
    :chat,
    :completion,
    :structured_json,
    :tool_calls,
    :streaming,
    :embeddings,
    :rerank,
    :vision,
    :audio,
    :realtime,
    :router_hidden_state,
    :verifier_scoring,
    :context_length,
    :max_output_tokens,
    :local_endpoint,
    :self_hosted_endpoint,
    :mock_deterministic,
    :live_provider_gated,
    :cost_profile
  ]

  @spec capabilities() :: [atom()]
  def capabilities, do: @capabilities

  @spec validate([atom() | String.t()]) ::
          {:ok, [atom()]} | {:error, {:unknown_capabilities, [term()]}}
  def validate(capabilities) when is_list(capabilities) do
    normalized = Enum.map(capabilities, &normalize/1)
    unknown = Enum.reject(normalized, &(&1 in @capabilities))

    case unknown do
      [] -> {:ok, normalized}
      values -> {:error, {:unknown_capabilities, values}}
    end
  end

  def validate(_capabilities), do: {:error, {:unknown_capabilities, [:invalid_capability_set]}}

  defp normalize(capability) when is_atom(capability), do: capability

  defp normalize(capability) when is_binary(capability) do
    Enum.find(@capabilities, capability, &(Atom.to_string(&1) == capability))
  end

  defp normalize(capability), do: capability
end
