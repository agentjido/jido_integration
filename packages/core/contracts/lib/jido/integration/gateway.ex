defmodule Jido.Integration.Gateway do
  @moduledoc """
  Operations gateway — admission control for outbound connector operations.

  The gateway applies policy checks before allowing operations to execute.
  It supports single policies and policy chains with conservative
  composition (most restrictive wins).
  """

  alias Jido.Integration.Gateway.Policy

  @doc """
  Check admission for an operation through a single policy.
  """
  @spec check(module(), map(), map()) :: Policy.decision()
  def check(policy_module, envelope, pressure \\ %{}) do
    partition = policy_module.partition_key(envelope)
    policy_module.on_pressure(partition, pressure)
  end

  @doc """
  Check admission through a chain of policies.

  Uses conservative composition: most restrictive decision wins.
  """
  @spec check_chain([module()], map(), map()) :: Policy.decision()
  def check_chain(policies, envelope, pressure \\ %{}) do
    decisions = Enum.map(policies, &check(&1, envelope, pressure))
    Policy.compose(decisions)
  end
end
