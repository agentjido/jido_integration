defmodule Jido.Integration.V2.WebhookRouter.Telemetry do
  @moduledoc """
  Package-owned `:telemetry` surface for hosted webhook route resolution.

  Event families:

  - `[:jido, :integration, :webhook_router, :route, :resolved]`
  - `[:jido, :integration, :webhook_router, :route, :failed]`

  Metadata is redacted through `Jido.Integration.V2.Redaction` and remains
  supplemental to durable ingress and control-plane truth.
  """

  alias Jido.Integration.V2.Redaction

  @type event_name :: :route_resolved | :route_failed

  @events %{
    route_resolved: [:jido, :integration, :webhook_router, :route, :resolved],
    route_failed: [:jido, :integration, :webhook_router, :route, :failed]
  }

  @spec event(event_name()) :: [atom()]
  def event(name), do: Map.fetch!(@events, name)

  @spec events() :: %{required(event_name()) => [atom()]}
  def events, do: @events

  @spec emit(event_name(), map(), map()) :: :ok
  def emit(name, measurements, metadata) when is_map(measurements) and is_map(metadata) do
    :telemetry.execute(event(name), measurements, Redaction.redact(metadata))
  end
end
