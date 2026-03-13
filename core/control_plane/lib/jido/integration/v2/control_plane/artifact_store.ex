defmodule Jido.Integration.V2.ControlPlane.ArtifactStore do
  @moduledoc """
  Durable artifact-reference truth owned by `control_plane`.
  """

  alias Jido.Integration.V2.ArtifactRef

  @callback put_artifact_ref(ArtifactRef.t()) :: :ok | {:error, term()}
  @callback fetch_artifact_ref(String.t()) :: {:ok, ArtifactRef.t()} | :error
  @callback list_artifact_refs(String.t()) :: [ArtifactRef.t()]
end
