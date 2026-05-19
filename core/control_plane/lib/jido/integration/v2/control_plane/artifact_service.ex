defmodule Jido.Integration.V2.ControlPlane.ArtifactService do
  @moduledoc """
  Artifact recording and readback service behind the control-plane facade.
  """

  alias Jido.Integration.V2.ControlPlane.ServiceCore

  defdelegate record_artifact(artifact_ref), to: ServiceCore
  defdelegate fetch_artifact(artifact_id), to: ServiceCore
  defdelegate run_artifacts(run_id), to: ServiceCore
end
