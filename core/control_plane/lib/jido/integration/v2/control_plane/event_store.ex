defmodule Jido.Integration.V2.ControlPlane.EventStore do
  @moduledoc """
  Durable append-only event-ledger behaviour owned by `control_plane`.
  """

  alias Jido.Integration.V2.Event

  @callback next_seq(String.t(), String.t() | nil) :: non_neg_integer()
  @callback append_events([Event.t()], keyword()) :: :ok | {:error, term()}
  @callback list_events(String.t()) :: [Event.t()]
end
