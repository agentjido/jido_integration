defmodule Jido.BoundaryBridge.RequestTranslator do
  @moduledoc """
  Pure request translation helpers for lower-boundary adapters.
  """

  alias Jido.BoundaryBridge.{AllocateBoundaryRequest, PolicyIntent, ReopenBoundaryRequest}

  @spec to_allocate_payload(AllocateBoundaryRequest.t()) :: map()
  def to_allocate_payload(%AllocateBoundaryRequest{} = request) do
    %{
      boundary_session_id: request.boundary_session_id,
      backend_kind: request.backend_kind,
      boundary_class: request.boundary_class,
      attach: Map.from_struct(request.attach),
      policy_intent: PolicyIntent.to_map(request.policy_intent),
      refs: Map.from_struct(request.refs),
      allocation_ttl_ms: request.allocation_ttl_ms,
      readiness_timeout_ms: request.readiness_timeout_ms,
      extensions: request.extensions,
      metadata: request.metadata
    }
  end

  @spec to_reopen_payload(ReopenBoundaryRequest.t()) :: map()
  def to_reopen_payload(%ReopenBoundaryRequest{} = request) do
    %{
      boundary_session_id: request.boundary_session_id,
      backend_kind: request.backend_kind,
      boundary_class: request.boundary_class,
      attach: Map.from_struct(request.attach),
      policy_intent: PolicyIntent.to_map(request.policy_intent),
      refs: Map.from_struct(request.refs),
      checkpoint_id: request.checkpoint_id,
      readiness_timeout_ms: request.readiness_timeout_ms,
      extensions: request.extensions,
      metadata: request.metadata
    }
  end
end
