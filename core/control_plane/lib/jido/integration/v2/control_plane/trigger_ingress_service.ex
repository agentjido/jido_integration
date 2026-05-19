defmodule Jido.Integration.V2.ControlPlane.TriggerIngressService do
  @moduledoc """
  Trigger admission and checkpoint service behind the control-plane facade.
  """

  alias Jido.Integration.V2.ControlPlane.ServiceCore

  defdelegate admit_trigger(trigger, opts \\ []), to: ServiceCore
  defdelegate record_rejected_trigger(trigger, reason), to: ServiceCore
  defdelegate fetch_trigger(tenant_id, connector_id, trigger_id, dedupe_key), to: ServiceCore

  defdelegate fetch_trigger_checkpoint(tenant_id, connector_id, trigger_id, partition_key),
    to: ServiceCore

  defdelegate put_trigger_checkpoint(checkpoint), to: ServiceCore
  defdelegate run_triggers(run_id), to: ServiceCore
end
