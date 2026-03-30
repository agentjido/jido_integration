defmodule Jido.BoundaryBridge.UnconfiguredAdapter do
  @moduledoc false

  @behaviour Jido.BoundaryBridge.Adapter

  def allocate(_payload, _opts),
    do: {:error, RuntimeError.exception("boundary adapter is not configured")}

  def reopen(_payload, _opts),
    do: {:error, RuntimeError.exception("boundary adapter is not configured")}

  def fetch_status(_boundary_session_id, _opts),
    do: {:error, RuntimeError.exception("boundary adapter is not configured")}

  def claim(_boundary_session_id, _payload, _opts),
    do: {:error, RuntimeError.exception("boundary adapter is not configured")}

  def heartbeat(_boundary_session_id, _payload, _opts),
    do: {:error, RuntimeError.exception("boundary adapter is not configured")}

  def stop(_boundary_session_id, _opts),
    do: {:error, RuntimeError.exception("boundary adapter is not configured")}
end
