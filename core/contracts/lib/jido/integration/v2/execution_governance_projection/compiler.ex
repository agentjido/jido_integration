defmodule Jido.Integration.V2.ExecutionGovernanceProjection.Compiler do
  @moduledoc """
  Compiles lower-gateway-owned governance projections into operational shadow sections.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ExecutionGovernanceProjection

  @type shadows :: %{
          required(:gateway_request) => map(),
          required(:runtime_request) => map(),
          required(:boundary_request) => map()
        }

  @spec compile!(ExecutionGovernanceProjection.t()) :: shadows()
  def compile!(%ExecutionGovernanceProjection{} = projection) do
    sandbox = projection.sandbox

    %{
      gateway_request: %{
        "allowed_operations" => projection.operations["allowed_operations"],
        "sandbox" => %{
          "level" => Contracts.validate_sandbox_level!(sandbox["level"]),
          "egress" => Contracts.validate_egress_policy!(sandbox["egress"]),
          "approvals" => Contracts.validate_approvals!(sandbox["approvals"]),
          "acceptable_attestation" => sandbox["acceptable_attestation"],
          "allowed_tools" => sandbox["allowed_tools"],
          "file_scope_ref" => sandbox["file_scope_ref"],
          "file_scope_hint" => sandbox["file_scope_hint"]
        }
      },
      runtime_request: %{
        "execution_family" => projection.placement["execution_family"],
        "placement_intent" => projection.placement["placement_intent"],
        "target_kind" => projection.placement["target_kind"],
        "logical_workspace_ref" => projection.workspace["logical_workspace_ref"],
        "routing_hints" => projection.topology["routing_hints"],
        "acceptable_attestation" => sandbox["acceptable_attestation"],
        "allowed_tools" => sandbox["allowed_tools"]
      },
      boundary_request: %{
        "boundary_class" => projection.boundary["boundary_class"],
        "requested_attach_mode" => projection.boundary["requested_attach_mode"],
        "requested_ttl_ms" => projection.boundary["requested_ttl_ms"],
        "session_mode" => projection.topology["session_mode"]
      }
    }
  end
end
