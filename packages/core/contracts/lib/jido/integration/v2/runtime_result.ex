defmodule Jido.Integration.V2.RuntimeResult do
  @moduledoc """
  Shared runtime emission envelope for direct, session, and stream execution.
  """

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Contracts

  @enforce_keys [:output]
  defstruct [:output, :runtime_ref_id, events: [], artifacts: []]

  @type event_spec :: %{
          required(:type) => String.t(),
          optional(:stream) => Contracts.event_stream(),
          optional(:level) => Contracts.event_level(),
          optional(:payload) => map(),
          optional(:payload_ref) => Contracts.payload_ref(),
          optional(:trace) => Contracts.trace_context(),
          optional(:target_id) => String.t(),
          optional(:session_id) => String.t(),
          optional(:runtime_ref_id) => String.t()
        }

  @type t :: %__MODULE__{
          output: map() | nil,
          runtime_ref_id: String.t() | nil,
          events: [event_spec()],
          artifacts: [ArtifactRef.t()]
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)

    struct!(__MODULE__, %{
      output: normalize_output(Map.get(attrs, :output)),
      runtime_ref_id: normalize_runtime_ref_id(Map.get(attrs, :runtime_ref_id)),
      events: normalize_events(Map.get(attrs, :events, [])),
      artifacts: normalize_artifacts(Map.get(attrs, :artifacts, []))
    })
  end

  defp normalize_output(nil), do: nil
  defp normalize_output(output) when is_map(output), do: output

  defp normalize_output(output) do
    raise ArgumentError, "runtime result output must be a map or nil, got: #{inspect(output)}"
  end

  defp normalize_runtime_ref_id(nil), do: nil

  defp normalize_runtime_ref_id(runtime_ref_id) do
    Contracts.validate_non_empty_string!(runtime_ref_id, "runtime_ref_id")
  end

  defp normalize_events(events) when is_list(events) do
    Enum.map(events, &normalize_event!/1)
  end

  defp normalize_events(events) do
    raise ArgumentError, "runtime result events must be a list, got: #{inspect(events)}"
  end

  defp normalize_event!(event) when is_map(event) do
    %{
      type: Contracts.validate_non_empty_string!(Contracts.fetch!(event, :type), "event.type"),
      stream: Contracts.validate_event_stream!(Contracts.get(event, :stream, :system)),
      level: Contracts.validate_event_level!(Contracts.get(event, :level, :info)),
      payload: normalize_payload(Contracts.get(event, :payload, %{})),
      payload_ref: normalize_payload_ref(Contracts.get(event, :payload_ref)),
      trace: Contracts.normalize_trace(Contracts.get(event, :trace, %{}))
    }
    |> maybe_put(
      :target_id,
      normalize_optional_string(Contracts.get(event, :target_id), "target_id")
    )
    |> maybe_put(
      :session_id,
      normalize_optional_string(Contracts.get(event, :session_id), "session_id")
    )
    |> maybe_put(
      :runtime_ref_id,
      normalize_optional_string(Contracts.get(event, :runtime_ref_id), "runtime_ref_id")
    )
  end

  defp normalize_event!(event) do
    raise ArgumentError, "runtime result event must be a map, got: #{inspect(event)}"
  end

  defp normalize_payload(payload) when is_map(payload), do: payload

  defp normalize_payload(payload) do
    raise ArgumentError, "runtime result event payload must be a map, got: #{inspect(payload)}"
  end

  defp normalize_payload_ref(nil), do: nil
  defp normalize_payload_ref(payload_ref), do: Contracts.normalize_payload_ref!(payload_ref)

  defp normalize_optional_string(nil, _field_name), do: nil

  defp normalize_optional_string(value, field_name) do
    Contracts.validate_non_empty_string!(value, field_name)
  end

  defp normalize_artifacts(artifacts) when is_list(artifacts) do
    Enum.map(artifacts, fn
      %ArtifactRef{} = artifact_ref ->
        artifact_ref

      artifact ->
        raise ArgumentError,
              "runtime result artifacts must be ArtifactRef structs, got: #{inspect(artifact)}"
    end)
  end

  defp normalize_artifacts(artifacts) do
    raise ArgumentError, "runtime result artifacts must be a list, got: #{inspect(artifacts)}"
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
