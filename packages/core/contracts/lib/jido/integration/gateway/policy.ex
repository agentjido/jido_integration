defmodule Jido.Integration.Gateway.Policy do
  @moduledoc """
  Gateway policy behaviour — defines admission control for operations.

  Policies decide whether an operation should be admitted, backed off,
  or shed based on current pressure. Multiple policies can be chained.

  ## Built-in Policies

  - `Jido.Integration.Gateway.Policy.Default` — always admits
  - `Jido.Integration.Gateway.Policy.RateLimit` — token-bucket rate limiting
  - `Jido.Integration.Gateway.Policy.Concurrent` — concurrent request limiting

  ## Decision Composition (Conservative)

  When chaining policies:
  1. If any policy returns `:shed` -> `:shed`
  2. Else if any returns `:backoff` -> `:backoff`
  3. Else -> `:admit`
  """

  @type decision :: :admit | :backoff | :shed
  @type capacity ::
          {:tokens, pos_integer() | :infinity}
          | {:concurrent, pos_integer()}
          | {:rate, pos_integer(), :per_second | :per_minute}

  @doc "Returns the partition key for this operation."
  @callback partition_key(operation_envelope :: map()) :: term()

  @doc "Returns the capacity for a given partition."
  @callback capacity(partition :: term()) :: capacity()

  @doc "Decide admission based on current pressure."
  @callback on_pressure(partition :: term(), pressure :: map()) :: decision()

  @optional_callbacks [partition_key: 1, capacity: 1]

  @doc """
  Compose multiple policy decisions conservatively.

  The most restrictive decision wins.
  """
  @spec compose([decision()]) :: decision()
  def compose(decisions) when is_list(decisions) do
    cond do
      :shed in decisions -> :shed
      :backoff in decisions -> :backoff
      true -> :admit
    end
  end
end
