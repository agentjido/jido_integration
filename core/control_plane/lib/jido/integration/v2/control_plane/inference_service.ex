defmodule Jido.Integration.V2.ControlPlane.InferenceService do
  @moduledoc """
  Inference recording and invocation service behind the control-plane facade.
  """

  alias Jido.Integration.V2.ControlPlane.ServiceCore

  defdelegate inference_capability_id(), to: ServiceCore
  defdelegate record_inference_attempt(spec), to: ServiceCore
  defdelegate invoke_inference(request, opts \\ []), to: ServiceCore
end
