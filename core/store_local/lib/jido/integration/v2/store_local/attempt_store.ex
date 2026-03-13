defmodule Jido.Integration.V2.StoreLocal.AttemptStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.AttemptStore

  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.StoreLocal.State
  alias Jido.Integration.V2.StoreLocal.Storage

  @impl true
  def put_attempt(%Attempt{} = attempt) do
    Storage.mutate(&State.put_attempt(&1, attempt))
  end

  @impl true
  def fetch_attempt(attempt_id) do
    Storage.read(&State.fetch_attempt(&1, attempt_id))
  end

  @impl true
  def update_attempt(attempt_id, status, output, runtime_ref_id, opts \\ []) do
    Storage.mutate(&State.update_attempt(&1, attempt_id, status, output, runtime_ref_id, opts))
  end

  def reset! do
    Storage.mutate(&State.reset_attempts/1)
  end
end
