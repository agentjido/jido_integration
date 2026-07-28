defmodule Jido.Integration.V2.Policy.EnforceSandbox do
  @moduledoc false

  @behaviour Jido.Integration.V2.Policy.Rule

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Credential

  @sandbox_rank %{strict: 0, standard: 1, none: 2}
  @egress_rank %{blocked: 0, restricted: 1, open: 2}
  @approval_rank %{none: 0, auto: 1, manual: 2}
  @runtime_bound_scope "runtime_bound"
  @broad_file_scopes ["/", "/home", "/home/home", "/tmp"]

  @impl true
  def evaluate(%Capability{}, %Credential{}, _input, %{gateway: gateway, contract: contract}) do
    requested = gateway.sandbox
    required = contract.sandbox
    missing_required_tools = missing_tools(required.allowed_tools, requested.allowed_tools)

    reasons =
      []
      |> maybe_add(
        weaker_sandbox?(requested.level, required.level),
        "sandbox level #{requested.level} is weaker than required #{required.level}"
      )
      |> maybe_add(
        weaker_egress?(requested.egress, required.egress),
        "egress #{requested.egress} exceeds required #{required.egress}"
      )
      |> maybe_add(
        not file_scope_satisfied?(requested.file_scope, required.file_scope, gateway),
        "file scope #{inspect(requested.file_scope)} does not satisfy required #{inspect(required.file_scope)}"
      )
      |> maybe_add(
        missing_required_tools != [],
        "sandbox tool allowlist is missing: #{Enum.join(missing_required_tools, ", ")}"
      )
      |> maybe_add(
        requested.level == :none and requested.approvals != :manual,
        "sandbox level none requires manual approvals"
      )
      |> maybe_add(
        weaker_approval?(requested.approvals, required.approvals),
        "approvals #{requested.approvals} do not satisfy required #{required.approvals}"
      )

    result(reasons)
  end

  defp weaker_sandbox?(requested, required),
    do: @sandbox_rank[requested] > @sandbox_rank[required]

  defp weaker_egress?(requested, required), do: @egress_rank[requested] > @egress_rank[required]

  defp weaker_approval?(requested, required),
    do: @approval_rank[requested] < @approval_rank[required]

  defp missing_tools(required, requested), do: required -- requested

  defp file_scope_satisfied?(_requested, nil, _gateway), do: true

  defp file_scope_satisfied?(requested, @runtime_bound_scope, gateway) do
    runtime_root =
      gateway
      |> Map.get(:metadata, %{})
      |> map_value(:opts, %{})
      |> map_value(:workspace_root)

    safe_runtime_scope?(requested) and requested == runtime_root
  end

  defp file_scope_satisfied?(requested, required, _gateway), do: requested == required

  defp safe_runtime_scope?(scope) when is_binary(scope) do
    Path.type(scope) == :absolute and Path.expand(scope) == scope and
      scope not in @broad_file_scopes
  end

  defp safe_runtime_scope?(_scope), do: false

  defp map_value(map, key, default \\ nil)

  defp map_value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp map_value(_value, _key, default), do: default

  defp maybe_add(reasons, true, reason), do: [reason | reasons]
  defp maybe_add(reasons, false, _reason), do: reasons

  defp result([]), do: :ok
  defp result(reasons), do: {:deny, Enum.reverse(reasons)}
end
