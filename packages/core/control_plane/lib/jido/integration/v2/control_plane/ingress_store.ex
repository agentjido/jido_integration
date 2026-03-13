defmodule Jido.Integration.V2.ControlPlane.IngressStore do
  @moduledoc """
  Durable ingress-truth behaviour owned by `control_plane`.
  """

  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord

  @callback transaction((-> term())) :: term()
  @callback rollback(term()) :: no_return()

  @callback reserve_dedupe(
              tenant_id :: String.t(),
              connector_id :: String.t(),
              trigger_id :: String.t(),
              dedupe_key :: String.t(),
              expires_at :: DateTime.t()
            ) :: :ok | {:error, :duplicate | term()}

  @callback put_trigger(TriggerRecord.t()) :: :ok | {:error, term()}
  @callback fetch_trigger(String.t(), String.t(), String.t(), String.t()) ::
              {:ok, TriggerRecord.t()} | :error
  @callback list_run_triggers(String.t()) :: [TriggerRecord.t()]

  @callback put_checkpoint(TriggerCheckpoint.t()) :: :ok | {:error, term()}
  @callback fetch_checkpoint(String.t(), String.t(), String.t(), String.t()) ::
              {:ok, TriggerCheckpoint.t()} | :error
end
