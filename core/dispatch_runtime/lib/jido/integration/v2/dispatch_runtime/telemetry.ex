defmodule Jido.Integration.V2.DispatchRuntime.Telemetry do
  @moduledoc """
  Package-owned `:telemetry` surface for async dispatch lifecycle observation.

  Event families:

  - `[:jido, :integration, :dispatch_runtime, :enqueue]`
  - `[:jido, :integration, :dispatch_runtime, :deliver]`
  - `[:jido, :integration, :dispatch_runtime, :retry]`
  - `[:jido, :integration, :dispatch_runtime, :dead_letter]`
  - `[:jido, :integration, :dispatch_runtime, :replay]`

  Metadata is redacted through `Jido.Integration.V2.Redaction` and remains
  supplemental to durable control-plane `Event` records.
  """

  alias Jido.Integration.V2.Redaction

  @type event_name :: :enqueue | :deliver | :retry | :dead_letter | :replay

  @events %{
    enqueue: [:jido, :integration, :dispatch_runtime, :enqueue],
    deliver: [:jido, :integration, :dispatch_runtime, :deliver],
    retry: [:jido, :integration, :dispatch_runtime, :retry],
    dead_letter: [:jido, :integration, :dispatch_runtime, :dead_letter],
    replay: [:jido, :integration, :dispatch_runtime, :replay]
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
