defmodule Jido.Integration.V2.Apps.InferenceOps.SelfHostedEndpointProvider do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.Inference.SelfHostedEndpointProvider

  alias Jido.Integration.V2.BackendManifest
  alias Jido.Integration.V2.CompatibilityResult
  alias Jido.Integration.V2.ConsumerManifest
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.EndpointDescriptor
  alias Jido.Integration.V2.InferenceExecutionContext
  alias Jido.Integration.V2.InferenceRequest
  alias SelfHostedInferenceCore.ConsumerManifest, as: SelfHostedConsumerManifest

  @impl true
  def ensure_endpoint(
        %InferenceRequest{} = request,
        %ConsumerManifest{} = consumer_manifest,
        %InferenceExecutionContext{} = context,
        opts
      ) do
    with {:ok, self_hosted_consumer_manifest} <-
           SelfHostedConsumerManifest.new(Map.from_struct(consumer_manifest)),
         {:ok, backend} <- fetch_target_backend(request),
         {:ok, raw_endpoint, raw_compatibility} <-
           SelfHostedInferenceCore.ensure_endpoint(
             request,
             self_hosted_consumer_manifest,
             Map.from_struct(context),
             owner_ref: Keyword.get(opts, :owner_ref, context.attempt_id),
             ttl_ms: Keyword.get(opts, :ttl_ms, 60_000),
             renewable?: Keyword.get(opts, :renewable?, true),
             await_timeout_ms: Keyword.get(opts, :await_timeout_ms, 5_000)
           ),
         {:ok, raw_backend_manifest} <- SelfHostedInferenceCore.fetch_backend_manifest(backend),
         endpoint_descriptor <- EndpointDescriptor.new!(Map.from_struct(raw_endpoint)),
         compatibility_result <-
           CompatibilityResult.new!(
             raw_compatibility
             |> Map.from_struct()
             |> Map.update!(:metadata, &Map.put(Map.new(&1), :route, :self_hosted))
           ),
         backend_manifest <- BackendManifest.new!(Map.from_struct(raw_backend_manifest)) do
      {:ok,
       %{
         endpoint_descriptor: endpoint_descriptor,
         compatibility_result: compatibility_result,
         backend_manifest: backend_manifest
       }}
    end
  end

  defp fetch_target_backend(%InferenceRequest{} = request) do
    case request.target_preference |> Map.new() |> Contracts.get(:backend) do
      nil -> {:error, {:missing_target_preference, :backend}}
      backend -> {:ok, Contracts.normalize_atomish!(backend, "target_preference.backend")}
    end
  end
end
