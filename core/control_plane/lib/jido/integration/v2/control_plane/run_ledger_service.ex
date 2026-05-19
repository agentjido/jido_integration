defmodule Jido.Integration.V2.ControlPlane.RunLedgerService do
  @moduledoc """
  Run, attempt, and event read service behind the control-plane facade.
  """

  alias Jido.Integration.V2.ControlPlane.ServiceCore

  defdelegate fetch_run(run_id), to: ServiceCore
  defdelegate runs(filters \\ %{}), to: ServiceCore
  defdelegate fetch_attempt(attempt_id), to: ServiceCore
  defdelegate attempts(run_id), to: ServiceCore
  defdelegate events(run_id), to: ServiceCore
end
