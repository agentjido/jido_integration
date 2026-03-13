defmodule Jido.Integration.V2.Apps.DevopsIncidentResponse.ExecuteTriggerHandler do
  @moduledoc false

  @behaviour Jido.Integration.V2.DispatchRuntime.Handler

  @impl true
  def execution_opts(trigger, %{attempt: attempt}) do
    {:ok,
     [
       actor_id: "devops-incident-response",
       tenant_id: trigger.tenant_id,
       allowed_operations: [trigger.capability_id],
       aggregator_id: "devops_incident_response",
       aggregator_epoch: attempt,
       trace_id: "devops-incident-response-attempt-#{attempt}"
     ]}
  end
end
