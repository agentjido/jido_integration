defmodule Jido.Integration.V2.StoreLocal.ArtifactStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.ArtifactStore

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.StoreLocal.State
  alias Jido.Integration.V2.StoreLocal.Storage

  @impl true
  def put_artifact_ref(%ArtifactRef{} = artifact_ref) do
    Storage.mutate(&State.put_artifact_ref(&1, artifact_ref))
  end

  @impl true
  def fetch_artifact_ref(artifact_id) do
    Storage.read(&State.fetch_artifact_ref(&1, artifact_id))
  end

  @impl true
  def list_artifact_refs(run_id) do
    Storage.read(&State.list_artifact_refs(&1, run_id))
  end

  def reset! do
    Storage.mutate(&State.reset_artifacts/1)
  end
end
