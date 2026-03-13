defmodule Jido.Integration.V2.ControlPlane.RunStore do
  @moduledoc """
  Durable run-truth behaviour owned by `control_plane`.
  """

  alias Jido.Integration.V2.Run

  @callback put_run(Run.t()) :: :ok | {:error, term()}
  @callback fetch_run(String.t()) :: {:ok, Run.t()} | :error
  @callback update_run(String.t(), atom(), map() | nil) :: :ok | {:error, term()}
end
