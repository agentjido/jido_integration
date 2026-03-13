defmodule Jido.Integration.V2.Policy do
  @moduledoc """
  Admission and execution governor for capability invocation.
  """

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.Gateway
  alias Jido.Integration.V2.Gateway.Policy, as: GatewayPolicy
  alias Jido.Integration.V2.Policy.EnforceSandbox
  alias Jido.Integration.V2.Policy.RequireActor
  alias Jido.Integration.V2.Policy.RequireEnvironment
  alias Jido.Integration.V2.Policy.RequireOperation
  alias Jido.Integration.V2.Policy.RequireRuntimeClass
  alias Jido.Integration.V2.Policy.RequireScopes
  alias Jido.Integration.V2.Policy.RequireTenant
  alias Jido.Integration.V2.Policy.RespectPressure
  alias Jido.Integration.V2.PolicyDecision
  alias Jido.Integration.V2.Redaction

  @rules [
    RequireOperation,
    RequireActor,
    RequireTenant,
    RequireEnvironment,
    RequireRuntimeClass,
    RequireScopes,
    EnforceSandbox,
    RespectPressure
  ]

  @spec evaluate(Capability.t(), Credential.t(), map(), map()) :: PolicyDecision.t()
  def evaluate(%Capability{} = capability, %Credential{} = credential, input, context) do
    gateway = normalize_gateway(capability, context)
    contract = GatewayPolicy.from_capability(capability)
    execution_policy = execution_policy(contract, gateway)
    audit_context = audit_context(capability, gateway, execution_policy)

    results =
      Enum.reduce(@rules, %{deny: [], shed: []}, fn rule, acc ->
        case apply_rule(rule, capability, credential, input, %{
               gateway: gateway,
               contract: contract
             }) do
          {:deny, reasons} ->
            Map.update!(acc, :deny, &(reasons ++ &1))

          {:shed, reasons} ->
            Map.update!(acc, :shed, &(reasons ++ &1))

          :ok ->
            acc
        end
      end)

    deny_reasons = Enum.uniq(results.deny)
    shed_reasons = Enum.uniq(results.shed)

    cond do
      deny_reasons != [] ->
        PolicyDecision.deny(deny_reasons, execution_policy, audit_context)

      shed_reasons != [] ->
        %PolicyDecision{
          status: :shed,
          reasons: shed_reasons,
          execution_policy: execution_policy,
          audit_context: audit_context
        }

      true ->
        PolicyDecision.allow(execution_policy, audit_context)
    end
  end

  defp apply_rule(rule, capability, credential, input, context) do
    case rule.evaluate(capability, credential, input, context) do
      :ok -> :ok
      {:deny, reasons} -> {:deny, reasons}
      {:shed, reasons} -> {:shed, reasons}
    end
  end

  defp normalize_gateway(%Capability{}, %Gateway{} = gateway), do: gateway

  defp normalize_gateway(%Capability{} = capability, context) when is_map(context) do
    context
    |> Map.new()
    |> Map.put_new(:runtime_class, capability.runtime_class)
    |> Gateway.new!()
  end

  defp execution_policy(contract, gateway) do
    requested_tools = gateway.sandbox.allowed_tools

    allowed_tools =
      case contract.sandbox.allowed_tools do
        [] -> requested_tools
        required_tools -> Enum.filter(required_tools, &(&1 in requested_tools))
      end

    %{
      runtime_class: gateway.runtime_class,
      sandbox: %{
        level: contract.sandbox.level,
        egress: contract.sandbox.egress,
        approvals: contract.sandbox.approvals,
        file_scope: contract.sandbox.file_scope || gateway.sandbox.file_scope,
        allowed_tools: allowed_tools
      }
    }
  end

  defp audit_context(capability, gateway, execution_policy) do
    %{
      actor_id: gateway.actor_id,
      tenant_id: gateway.tenant_id,
      environment: gateway.environment,
      trace_id: gateway.trace_id,
      connector_id: capability.connector,
      capability_id: capability.id,
      runtime_class: gateway.runtime_class,
      credential_ref_id: gateway.credential_ref && gateway.credential_ref.id,
      pressure: pressure_snapshot(gateway.metadata),
      sandbox: execution_policy.sandbox,
      allowed_operations: gateway.allowed_operations
    }
  end

  defp pressure_snapshot(metadata) when is_map(metadata) do
    case Map.get(metadata, :pressure, Map.get(metadata, "pressure")) do
      pressure when is_map(pressure) -> Redaction.redact(pressure)
      _other -> nil
    end
  end
end
