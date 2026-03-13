defmodule Jido.Integration.V2.Conformance.Suites.PolicyContract do
  @moduledoc false

  alias Jido.Integration.V2.Conformance.CheckResult
  alias Jido.Integration.V2.Conformance.SuiteResult
  alias Jido.Integration.V2.Conformance.SuiteSupport
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Gateway.Policy

  @spec run(map()) :: SuiteResult.t()
  def run(%{manifest: manifest}) do
    checks =
      Enum.flat_map(manifest.capabilities, fn capability ->
        metadata = capability.metadata
        policy = Contracts.get(metadata, :policy, %{})
        sandbox = Contracts.get(policy, :sandbox, %{})
        environment = Contracts.get(policy, :environment, %{})

        [
          SuiteSupport.check(
            "#{capability.id}.required_scopes.explicit",
            SuiteSupport.declared?(metadata, :required_scopes),
            "capabilities must declare required_scopes explicitly"
          ),
          SuiteSupport.check(
            "#{capability.id}.policy.explicit",
            SuiteSupport.declared?(metadata, :policy),
            "capabilities must declare policy metadata explicitly"
          ),
          SuiteSupport.check(
            "#{capability.id}.environment.allowed",
            is_list(Contracts.get(environment, :allowed, [])) and
              Contracts.get(environment, :allowed, []) != [],
            "policy.environment.allowed must be a non-empty list"
          ),
          SuiteSupport.check(
            "#{capability.id}.sandbox.declared",
            is_map(sandbox),
            "policy.sandbox must be a map"
          ),
          SuiteSupport.check(
            "#{capability.id}.sandbox.allowed_tools",
            is_list(Contracts.get(sandbox, :allowed_tools, [])) and
              Contracts.get(sandbox, :allowed_tools, []) != [],
            "policy.sandbox.allowed_tools must be a non-empty list"
          ),
          maybe_check_session_file_scope(capability, sandbox)
        ] ++ policy_normalization_checks(capability)
      end)

    SuiteResult.from_checks(
      :policy_contract,
      List.flatten(checks),
      "Policy metadata declares sandbox posture, scopes, and runtime guardrails"
    )
  end

  defp maybe_check_session_file_scope(%{runtime_class: :session} = capability, sandbox) do
    SuiteSupport.check(
      "#{capability.id}.sandbox.file_scope",
      is_binary(Contracts.get(sandbox, :file_scope)) and
        String.trim(Contracts.get(sandbox, :file_scope)) != "",
      "session capabilities must declare sandbox.file_scope"
    )
  end

  defp maybe_check_session_file_scope(capability, _sandbox) do
    CheckResult.pass("#{capability.id}.sandbox.file_scope.na")
  end

  defp policy_normalization_checks(capability) do
    case normalize_policy(capability) do
      {:ok, contract} ->
        [
          SuiteSupport.check(
            "#{capability.id}.policy.normalizes",
            true,
            "capability policy normalized successfully"
          ),
          SuiteSupport.check(
            "#{capability.id}.runtime.allowed",
            capability.runtime_class in contract.runtime.allowed,
            "normalized policy must allow the declared runtime class"
          )
        ]

      {:error, message} ->
        [
          CheckResult.fail("#{capability.id}.policy.normalizes", message)
        ]
    end
  end

  defp normalize_policy(capability) do
    {:ok, Policy.from_capability(capability)}
  rescue
    error -> {:error, Exception.message(error)}
  end
end
