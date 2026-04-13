defmodule Jido.Integration.V2.StoreLocal.RunStore do
  @moduledoc false

  @behaviour Jido.Integration.V2.ControlPlane.RunStore

  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.StoreLocal.State
  alias Jido.Integration.V2.StoreLocal.Storage

  @impl true
  def put_run(%Run{} = run) do
    Storage.mutate(&State.put_run(&1, run))
  end

  @impl true
  def fetch_run(run_id) do
    Storage.read(&State.fetch_run(&1, run_id))
  end

  @impl true
  def update_run(run_id, status, result) do
    Storage.mutate(&State.update_run(&1, run_id, status, result))
  end

  def reset! do
    Storage.mutate(&State.reset_runs/1)
  end
end
