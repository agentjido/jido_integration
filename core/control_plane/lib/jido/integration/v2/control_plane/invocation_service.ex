defmodule Jido.Integration.V2.ControlPlane.InvocationService do
  @moduledoc """
  Run invocation and retry service behind the control-plane facade.
  """

  alias Jido.Integration.V2.ControlPlane.ServiceCore

  defdelegate invoke(request), to: ServiceCore
  defdelegate invoke(capability_id, input, opts \\ []), to: ServiceCore
  defdelegate execute_run(run_id, attempt_number, opts \\ []), to: ServiceCore
end
