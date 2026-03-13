defmodule Jido.Integration.Test.TelemetryHandler do
  @moduledoc false

  @valid_include [:event, :measurements, :metadata]

  def attach(handler_id, event, opts \\ []) do
    :telemetry.attach(handler_id, event, &__MODULE__.handle_event/4, config(opts))
  end

  def attach_many(handler_id, events, opts \\ []) do
    :telemetry.attach_many(handler_id, events, &__MODULE__.handle_event/4, config(opts))
  end

  def handle_event(event, measurements, metadata, %{
        recipient: recipient,
        tag: tag,
        include: include
      }) do
    payload =
      Enum.map(include, fn
        :event -> event
        :measurements -> measurements
        :metadata -> metadata
      end)

    send(recipient, List.to_tuple([tag | payload]))
  end

  defp config(opts) do
    include =
      opts
      |> Keyword.get(:include, [:metadata])
      |> validate_include!()

    %{
      recipient: Keyword.get(opts, :recipient, self()),
      tag: Keyword.get(opts, :tag, :telemetry),
      include: include
    }
  end

  defp validate_include!(include) when is_list(include) do
    Enum.each(include, fn item ->
      unless item in @valid_include do
        raise ArgumentError,
              "unsupported telemetry payload entry #{inspect(item)}; expected one of #{inspect(@valid_include)}"
      end
    end)

    include
  end

  defp validate_include!(include) do
    raise ArgumentError, "expected :include to be a list, got: #{inspect(include)}"
  end
end
