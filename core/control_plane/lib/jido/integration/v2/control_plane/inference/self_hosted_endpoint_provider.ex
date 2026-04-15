defmodule Jido.Integration.V2.ControlPlane.Inference.SelfHostedEndpointProvider do
  @moduledoc """
  Optional provider seam for self-hosted inference endpoint resolution.

  `core/control_plane` depends on this behavior only. Concrete self-hosted
  runtime wiring belongs in an optional app or bridge package.
  """

  alias Jido.Integration.V2.BackendManifest
  alias Jido.Integration.V2.CompatibilityResult
  alias Jido.Integration.V2.ConsumerManifest
  alias Jido.Integration.V2.EndpointDescriptor
  alias Jido.Integration.V2.InferenceExecutionContext
  alias Jido.Integration.V2.InferenceRequest

  @type resolution :: %{
          endpoint_descriptor: EndpointDescriptor.t(),
          compatibility_result: CompatibilityResult.t(),
          backend_manifest: BackendManifest.t()
        }

  @callback ensure_endpoint(
              InferenceRequest.t(),
              ConsumerManifest.t(),
              InferenceExecutionContext.t(),
              keyword()
            ) :: {:ok, resolution()} | {:error, term()}
end
