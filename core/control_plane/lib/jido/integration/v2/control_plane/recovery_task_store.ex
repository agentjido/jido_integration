defmodule Jido.Integration.V2.ControlPlane.RecoveryTaskStore do
  @moduledoc """
  Durable recovery-task ownership for provider attempts with unknown outcomes.

  Claims are fenced by an opaque claim reference. A worker that loses its
  claim cannot later overwrite a newer reconciliation decision.
  """

  alias Jido.Integration.V2.RecoveryTask

  @callback put_task(RecoveryTask.t()) ::
              {:ok, RecoveryTask.t(), :inserted | :existing} | {:error, term()}
  @callback fetch_task(String.t()) :: {:ok, RecoveryTask.t()} | :error
  @callback list_tasks(map()) :: [RecoveryTask.t()]
  @callback list_due(DateTime.t(), pos_integer()) :: [RecoveryTask.t()]
  @callback claim_task(String.t(), String.t(), DateTime.t(), DateTime.t()) ::
              {:ok, RecoveryTask.t()} | {:error, term()}
  @callback transition_task(
              String.t(),
              String.t(),
              atom(),
              DateTime.t(),
              map(),
              DateTime.t()
            ) ::
              {:ok, RecoveryTask.t()} | {:error, term()}
end
