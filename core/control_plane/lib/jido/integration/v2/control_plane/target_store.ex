defmodule Jido.Integration.V2.ControlPlane.TargetStore do
  @moduledoc """
  Durable target-descriptor truth owned by `control_plane`.
  """

  alias Jido.Integration.V2.TargetDescriptor

  @callback put_target_descriptor(TargetDescriptor.t()) :: :ok | {:error, term()}
  @callback fetch_target_descriptor(String.t()) :: {:ok, TargetDescriptor.t()} | :error
  @callback list_target_descriptors() :: [TargetDescriptor.t()]
end
