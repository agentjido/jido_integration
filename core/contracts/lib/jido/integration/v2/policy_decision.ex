defmodule Jido.Integration.V2.PolicyDecision do
  @moduledoc """
  Captures the control-plane admission decision for a run.
  """

  @enforce_keys [:status, :execution_policy, :audit_context]
  defstruct [:status, reasons: [], execution_policy: %{}, audit_context: %{}]

  @type t :: %__MODULE__{
          status: :allowed | :denied | :shed,
          reasons: [String.t()],
          execution_policy: map(),
          audit_context: map()
        }

  @spec allow(map(), map()) :: t()
  def allow(execution_policy, audit_context)
      when is_map(execution_policy) and is_map(audit_context) do
    %__MODULE__{
      status: :allowed,
      reasons: [],
      execution_policy: execution_policy,
      audit_context: audit_context
    }
  end

  @spec deny([String.t()], map(), map()) :: t()
  def deny(reasons, execution_policy, audit_context)
      when is_list(reasons) and is_map(execution_policy) and is_map(audit_context) do
    %__MODULE__{
      status: :denied,
      reasons: reasons,
      execution_policy: execution_policy,
      audit_context: audit_context
    }
  end

  @spec shed([String.t()], map(), map()) :: t()
  def shed(reasons, execution_policy, audit_context)
      when is_list(reasons) and is_map(execution_policy) and is_map(audit_context) do
    %__MODULE__{
      status: :shed,
      reasons: reasons,
      execution_policy: execution_policy,
      audit_context: audit_context
    }
  end
end
