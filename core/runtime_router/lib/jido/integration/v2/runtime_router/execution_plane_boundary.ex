defmodule Jido.Integration.V2.RuntimeRouter.ExecutionPlaneBoundary do
  @moduledoc """
  Maps Jido/Citadel governance into the Execution Plane runtime-client boundary.

  This module owns the upstream fallback ladder. Each ladder rung becomes a
  separate runtime-client `execute/2` call with a single acceptable attestation
  class. The Execution Plane node never receives or interprets the ladder.
  """

  alias ExecutionPlane.Admission.Request
  alias ExecutionPlane.Authority.Ref, as: AuthorityRef
  alias ExecutionPlane.ExecutionResult
  alias ExecutionPlane.Placement.Surface
  alias ExecutionPlane.Provenance
  alias ExecutionPlane.Runtime.Constraint
  alias ExecutionPlane.Sandbox.AcceptableAttestation
  alias ExecutionPlane.Sandbox.Profile
  alias Jido.Integration.V2.ExecutionGovernanceProjection

  @type attempt_record :: %{
          required(:rung) => pos_integer(),
          required(:attestation_class) => String.t(),
          required(:request_id) => String.t(),
          required(:status) => :succeeded | :rejected,
          optional(:result) => ExecutionResult.t(),
          optional(:reason) => term()
        }

  @spec admission_request(ExecutionGovernanceProjection.t(), map(), keyword()) :: Request.t()
  def admission_request(%ExecutionGovernanceProjection{} = projection, payload, opts \\ [])
      when is_map(payload) and is_list(opts) do
    attestation_classes =
      Keyword.get(opts, :acceptable_attestation, acceptable_ladder(projection))

    Request.new!(
      request_id: Keyword.get(opts, :request_id, request_id(projection, attestation_classes)),
      lane_id: Keyword.get(opts, :lane_id, lane_id(projection)),
      operation: Keyword.get(opts, :operation, primary_operation(projection)),
      payload: payload,
      authority_ref: authority_ref(projection),
      sandbox_profile: sandbox_profile(projection),
      acceptable_attestation:
        AcceptableAttestation.new!(
          classes: attestation_classes,
          priority_order: attestation_classes
        ),
      placement: placement(projection),
      constraints: constraints(projection),
      provenance:
        Provenance.node_admitted(%{
          owner: "jido_integration",
          details: %{
            "execution_governance_id" => projection.execution_governance_id,
            "execution_governance_hash" => ExecutionGovernanceProjection.payload_hash(projection)
          }
        }),
      metadata:
        %{
          "execution_governance_id" => projection.execution_governance_id,
          "execution_governance_hash" => ExecutionGovernanceProjection.payload_hash(projection)
        }
        |> Map.merge(Keyword.get(opts, :metadata, %{}))
    )
  end

  @spec execute_fallback_ladder(
          ExecutionGovernanceProjection.t(),
          map(),
          module(),
          keyword()
        ) ::
          {:ok, ExecutionResult.t(), [attempt_record()]}
          | {:error, term(), [attempt_record()]}
  def execute_fallback_ladder(
        %ExecutionGovernanceProjection{} = projection,
        payload,
        runtime_client,
        opts \\ []
      )
      when is_map(payload) and is_atom(runtime_client) and is_list(opts) do
    projection
    |> acceptable_ladder()
    |> Enum.with_index(1)
    |> Enum.reduce_while([], fn {attestation_class, rung}, attempts ->
      request =
        admission_request(
          projection,
          payload,
          Keyword.merge(opts,
            acceptable_attestation: [attestation_class],
            request_id: request_id(projection, [attestation_class], rung),
            metadata: Map.put(Keyword.get(opts, :metadata, %{}), "fallback_rung", rung)
          )
        )

      case runtime_client.execute(request, Keyword.get(opts, :runtime_client_opts, [])) do
        {:ok, %ExecutionResult{} = result} ->
          attempt = success_attempt(rung, attestation_class, request, result)
          {:halt, {:ok, result, Enum.reverse([attempt | attempts])}}

        {:error, %ExecutionResult{} = result} ->
          attempt = rejection_attempt(rung, attestation_class, request, result)
          {:cont, [attempt | attempts]}

        {:error, reason} ->
          attempt = rejection_attempt(rung, attestation_class, request, reason)
          {:cont, [attempt | attempts]}
      end
    end)
    |> case do
      {:ok, _result, _attempts} = ok ->
        ok

      attempts ->
        {:error, :execution_plane_ladder_exhausted, Enum.reverse(attempts)}
    end
  end

  @spec acceptable_ladder(ExecutionGovernanceProjection.t()) :: [String.t()]
  def acceptable_ladder(%ExecutionGovernanceProjection{sandbox: sandbox}) do
    sandbox
    |> Map.fetch!("acceptable_attestation")
    |> Enum.map(&to_string/1)
  end

  defp authority_ref(%ExecutionGovernanceProjection{} = projection) do
    authority = projection.authority_ref

    AuthorityRef.new!(
      ref: "citadel://authority/#{authority["decision_id"]}",
      payload_hash: authority["decision_hash"],
      metadata: authority
    )
  end

  defp sandbox_profile(%ExecutionGovernanceProjection{} = projection) do
    Profile.new!(
      profile_ref: "citadel://execution-governance/#{projection.execution_governance_id}",
      bundle_hash: ExecutionGovernanceProjection.payload_hash(projection),
      opaque_bundle: ExecutionGovernanceProjection.dump(projection),
      metadata: projection.sandbox
    )
  end

  defp placement(%ExecutionGovernanceProjection{} = projection) do
    Surface.new!(
      surface_kind: projection.placement["placement_intent"],
      family: projection.placement["execution_family"],
      metadata: projection.placement
    )
  end

  defp constraints(%ExecutionGovernanceProjection{} = projection) do
    [
      constraint("wall_clock_budget_ms", projection.resources["wall_clock_budget_ms"]),
      constraint("requested_ttl_ms", projection.boundary["requested_ttl_ms"])
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp constraint(_name, nil), do: nil
  defp constraint(name, value), do: Constraint.new!(name: name, value: value)

  defp lane_id(%ExecutionGovernanceProjection{placement: %{"execution_family" => "json_rpc"}}),
    do: "jsonrpc"

  defp lane_id(%ExecutionGovernanceProjection{placement: %{"execution_family" => family}}),
    do: family

  defp primary_operation(%ExecutionGovernanceProjection{} = projection) do
    projection.operations["allowed_operations"]
    |> List.first()
  end

  defp request_id(projection, attestation_classes, rung \\ nil) do
    suffix =
      attestation_classes
      |> Enum.join("+")
      |> String.replace(~r/[^A-Za-z0-9_.-]+/, "_")

    ["ep", projection.execution_governance_id, suffix, rung]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp success_attempt(rung, attestation_class, request, result) do
    %{
      rung: rung,
      attestation_class: attestation_class,
      request_id: request.request_id,
      status: :succeeded,
      result: result
    }
  end

  defp rejection_attempt(rung, attestation_class, request, result_or_reason) do
    %{
      rung: rung,
      attestation_class: attestation_class,
      request_id: request.request_id,
      status: :rejected,
      reason: result_or_reason
    }
  end
end
