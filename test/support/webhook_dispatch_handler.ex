defmodule Jido.Integration.Test.WebhookDispatchHandler do
  @moduledoc false

  def handle_trigger(event, context) when is_map(event) do
    {:ok,
     %{
       "event_type" =>
         get_in(event.payload, ["headers", "x-github-event"]) ||
           get_in(event.payload, ["headers", "x-event-type"]) ||
           "unknown",
       "delivery_id" => event.dedupe_key,
       "payload" => get_in(event.payload, ["body"]) || %{},
       "trigger_id" => event.trigger_id,
       "run_id" => context.run_id
     }}
  end
end
