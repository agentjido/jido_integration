defmodule Jido.Integration.V2.BrainIngress.SubmissionDedupe do
  @moduledoc false

  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.Contracts

  @field "submission_dedupe_key"

  @spec key!(BrainInvocation.t()) :: String.t()
  def key!(%BrainInvocation{} = invocation) do
    invocation.extensions
    |> Map.get(@field)
    |> Contracts.validate_non_empty_string!("brain_invocation.extensions.submission_dedupe_key")
  end
end
