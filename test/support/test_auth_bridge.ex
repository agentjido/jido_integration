defmodule Jido.Integration.Test.TestAuthBridge do
  @moduledoc """
  Test implementation of the Auth.Bridge behaviour.

  Provides server-shaped lifecycle responses for testing without a real host
  framework. It models the bridge as a thin host boundary, not as an alternate
  auth engine.
  """

  @behaviour Jido.Integration.Auth.Bridge

  @impl true
  def start_install(connector_id, tenant_id, _opts) do
    connection_id = random_id("conn")

    session_state = %{
      "connector_id" => connector_id,
      "tenant_id" => tenant_id,
      "connection_id" => connection_id,
      "state" => random_id("state"),
      "nonce" => :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    }

    {:ok,
     %{
       auth_url: "https://example.com/oauth/authorize?connector=#{connector_id}",
       connection_id: connection_id,
       session_state: session_state
     }}
  end

  @impl true
  def handle_callback(connector_id, params, session_state) do
    if Map.has_key?(params, "code") do
      connection_id = Map.get(session_state, "connection_id", random_id("conn"))
      auth_ref = "auth:#{connector_id}:#{connection_id}"
      {:ok, %{connection_id: connection_id, state: :connected, auth_ref: auth_ref}}
    else
      {:error, :missing_code}
    end
  end

  @impl true
  def get_token(connection_id) do
    auth_ref = "auth:test:#{connection_id}"

    {:ok,
     %{
       auth_ref: auth_ref,
       token_ref: auth_ref,
       expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
     }}
  end

  @impl true
  def revoke(_connection_id, _reason) do
    :ok
  end

  @impl true
  def connection_health(_connection_id) do
    {:ok, %{status: :healthy, details: %{}}}
  end

  @impl true
  def check_scopes(_connection_id, required_scopes) do
    # In tests, configure which scopes are available via process dictionary
    available = Process.get(:test_scopes, ["repo", "public_repo", "read:org"])
    missing = required_scopes -- available

    if missing == [] do
      :ok
    else
      {:error, %{missing_scopes: missing}}
    end
  end

  defp random_id(prefix) do
    prefix <> "_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
