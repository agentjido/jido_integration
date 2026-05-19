defmodule Jido.Integration.V2.ControlPlane.PolicyService do
  @moduledoc """
  Policy admission helpers behind the control-plane facade.
  """

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Gateway
  alias Jido.Integration.V2.Policy
  alias Jido.Integration.V2.PolicyDecision

  @spec evaluate(Capability.t(), Credential.t() | nil, CredentialRef.t() | nil, map(), keyword()) ::
          PolicyDecision.t()
  def evaluate(capability, resolved_credential, credential_ref, input, opts) do
    gateway =
      Gateway.new!(%{
        actor_id: Keyword.get(opts, :actor_id),
        tenant_id: Keyword.get(opts, :tenant_id),
        environment: Keyword.get(opts, :environment),
        trace_id: Keyword.get(opts, :trace_id),
        credential_ref: credential_ref,
        runtime_class: capability.runtime_class,
        allowed_operations: Keyword.get(opts, :allowed_operations, []),
        sandbox: effective_sandbox(capability, opts),
        metadata: %{
          opts: Enum.into(opts, %{}),
          pressure: Keyword.get(opts, :pressure)
        }
      })

    Policy.evaluate(capability, resolved_credential, input, gateway)
  end

  @spec rejection_snapshot(PolicyDecision.t()) :: map()
  def rejection_snapshot(decision) do
    %{
      policy:
        decision.audit_context
        |> Map.put(:reasons, decision.reasons)
        |> Map.put(:status, decision.status)
    }
  end

  @spec rejection_run_status(PolicyDecision.t()) :: :denied | :shed
  def rejection_run_status(%PolicyDecision{status: :denied}), do: :denied
  def rejection_run_status(%PolicyDecision{status: :shed}), do: :shed

  @spec rejection_error(PolicyDecision.t()) :: :policy_denied | :policy_shed
  def rejection_error(%PolicyDecision{status: :denied}), do: :policy_denied
  def rejection_error(%PolicyDecision{status: :shed}), do: :policy_shed

  @spec rejection_event_type(PolicyDecision.t()) :: String.t()
  def rejection_event_type(%PolicyDecision{status: :denied}), do: "run.denied"
  def rejection_event_type(%PolicyDecision{status: :shed}), do: "run.shed"

  @spec rejection_audit_event_type(PolicyDecision.t()) :: String.t()
  def rejection_audit_event_type(%PolicyDecision{status: :denied}), do: "audit.policy_denied"
  def rejection_audit_event_type(%PolicyDecision{status: :shed}), do: "audit.policy_shed"

  @spec rejection_audit_level(PolicyDecision.t()) :: :error | :warn
  def rejection_audit_level(%PolicyDecision{status: :denied}), do: :error
  def rejection_audit_level(%PolicyDecision{status: :shed}), do: :warn

  defp effective_sandbox(capability, opts) do
    contract_sandbox =
      capability.metadata
      |> Contracts.get(:policy, %{})
      |> Contracts.get(:sandbox, %{})

    case Keyword.fetch(opts, :sandbox) do
      {:ok, sandbox} when is_map(sandbox) ->
        %{
          level: Contracts.get(sandbox, :level, Contracts.get(contract_sandbox, :level)),
          egress: Contracts.get(sandbox, :egress, Contracts.get(contract_sandbox, :egress)),
          approvals:
            Contracts.get(sandbox, :approvals, Contracts.get(contract_sandbox, :approvals)),
          file_scope:
            Contracts.get(sandbox, :file_scope, Contracts.get(contract_sandbox, :file_scope)),
          allowed_tools:
            Contracts.get(
              sandbox,
              :allowed_tools,
              Contracts.get(contract_sandbox, :allowed_tools, [])
            )
        }

      {:ok, sandbox} ->
        sandbox

      :error ->
        contract_sandbox
    end
  end
end
