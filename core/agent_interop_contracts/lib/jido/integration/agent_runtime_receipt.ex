defmodule Jido.Integration.AgentRuntimeReceipt do
  @moduledoc """
  Compatibility namespace for `AgentRuntimeReceipt.v1`.
  """

  alias Jido.Integration.AgentInterop.Receipt

  @type t :: Receipt.t()

  defdelegate can_transition?(from_status, to_status), to: Receipt
  defdelegate contract_name(), to: Receipt
  defdelegate new(attrs), to: Receipt
  defdelegate new!(attrs), to: Receipt
  defdelegate statuses(), to: Receipt
  defdelegate terminal_statuses(), to: Receipt
  defdelegate to_map(receipt), to: Receipt
  defdelegate transition(receipt, next_status, opts \\ []), to: Receipt
  defdelegate transition!(receipt, next_status, opts \\ []), to: Receipt
end
