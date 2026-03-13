defmodule Jido.Integration.V2.Policy.Rule do
  @moduledoc """
  Behaviour for admission rules.
  """

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Credential

  @callback evaluate(Capability.t(), Credential.t(), map(), map()) :: :ok | {:deny, [String.t()]}
end
