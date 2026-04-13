defmodule Jido.Integration.V2.ControlPlane.AttemptStore do
  @moduledoc """
  Durable attempt-truth behaviour owned by `control_plane`.
  """

  alias Jido.Integration.V2.Attempt

  @callback put_attempt(Attempt.t()) :: :ok | {:error, term()}
  @callback fetch_attempt(String.t()) :: {:ok, Attempt.t()} | :error
  @callback list_attempts(String.t()) :: [Attempt.t()]
  @callback update_attempt(String.t(), atom(), map() | nil, String.t() | nil, keyword()) ::
              :ok | {:error, term()}
end
