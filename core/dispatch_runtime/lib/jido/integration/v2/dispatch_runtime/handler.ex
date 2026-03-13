defmodule Jido.Integration.V2.DispatchRuntime.Handler do
  @moduledoc """
  Host-controlled trigger handler registration for async dispatch execution.
  """

  alias Jido.Integration.V2.DispatchRuntime.Dispatch
  alias Jido.Integration.V2.TriggerRecord

  @type context :: %{
          required(:dispatch) => Dispatch.t(),
          required(:attempt) => pos_integer(),
          required(:run_id) => String.t()
        }

  @callback execution_opts(TriggerRecord.t(), context()) :: {:ok, keyword()}
end
