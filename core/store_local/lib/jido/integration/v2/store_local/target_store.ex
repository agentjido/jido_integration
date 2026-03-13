defmodule Jido.Integration.V2.StoreLocal.TargetStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.TargetStore

  alias Jido.Integration.V2.StoreLocal.State
  alias Jido.Integration.V2.StoreLocal.Storage
  alias Jido.Integration.V2.TargetDescriptor

  @impl true
  def put_target_descriptor(%TargetDescriptor{} = descriptor) do
    Storage.mutate(&State.put_target_descriptor(&1, descriptor))
  end

  @impl true
  def fetch_target_descriptor(target_id) do
    Storage.read(&State.fetch_target_descriptor(&1, target_id))
  end

  @impl true
  def list_target_descriptors do
    Storage.read(&State.list_target_descriptors/1)
  end

  def reset! do
    Storage.mutate(&State.reset_targets/1)
  end
end
