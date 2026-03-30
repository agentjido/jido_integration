defmodule Jido.BoundaryBridge.DescriptorNormalizer do
  @moduledoc """
  Pure descriptor normalization helpers for lower-boundary adapters.
  """

  alias Jido.BoundaryBridge.{BoundarySessionDescriptor, Contracts, PolicyIntent}

  @spec normalize(BoundarySessionDescriptor.t() | map()) ::
          {:ok, BoundarySessionDescriptor.t()} | {:error, Exception.t()}
  def normalize(%BoundarySessionDescriptor{} = descriptor), do: {:ok, descriptor}

  def normalize(%{session: session}) when is_map(session) do
    session
    |> from_session_payload()
    |> BoundarySessionDescriptor.new()
  end

  def normalize(attrs) when is_map(attrs) or is_list(attrs) do
    BoundarySessionDescriptor.new(Map.new(attrs))
  end

  def normalize(other) do
    {:error,
     ArgumentError.exception(
       "boundary descriptor must be a map, keyword list, or #{inspect(BoundarySessionDescriptor)}, got: #{inspect(other)}"
     )}
  end

  defp from_session_payload(session) do
    session = Map.new(session)
    metadata = Contracts.get(session, :metadata, %{})
    attach = Contracts.get(metadata, :attach, %{})

    refs =
      Map.merge(Contracts.get(metadata, :refs, %{}), %{
        target_id: Contracts.get(Contracts.get(session, :target, %{}), :target_id),
        correlation_id: Contracts.get(metadata, :correlation_id),
        request_id: Contracts.get(metadata, :request_id)
      })

    %{
      descriptor_version: 1,
      boundary_session_id: Contracts.get(session, :session_id),
      backend_kind: Contracts.get(Contracts.get(session, :backend, %{}), :backend_kind, :unknown),
      boundary_class: Contracts.get(metadata, :boundary_class),
      status: Contracts.get(session, :status, :starting),
      attach_ready?: Contracts.get(metadata, :attach_ready?, false),
      workspace: %{
        workspace_root: Contracts.get(metadata, :workspace_root),
        snapshot_ref: Contracts.get(metadata, :snapshot_ref),
        artifact_namespace: Contracts.get(metadata, :artifact_namespace)
      },
      attach: %{
        mode: Contracts.get(attach, :mode, :not_applicable),
        execution_surface: Contracts.get(attach, :execution_surface),
        working_directory: Contracts.get(attach, :working_directory)
      },
      checkpointing: %{
        supported?: Contracts.get(metadata, :checkpoint_supported?, false),
        last_checkpoint_id: Contracts.get(session, :last_checkpoint_id)
      },
      policy_intent_echo:
        PolicyIntent.to_map(PolicyIntent.new!(Contracts.get(metadata, :policy_intent, %{}))),
      refs: refs,
      extensions: Contracts.get(metadata, :extensions, %{}),
      metadata: metadata
    }
  end
end
