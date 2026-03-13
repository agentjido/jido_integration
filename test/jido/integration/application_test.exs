defmodule Jido.Integration.ApplicationTest do
  use ExUnit.Case, async: false

  test "default runtime services are started by the OTP application, excluding the host-owned dispatch consumer" do
    assert Process.whereis(Jido.Integration.Registry)
    assert Process.whereis(Jido.Integration.Auth.Server)
    assert Process.whereis(Jido.Integration.Webhook.Router)
    assert Process.whereis(Jido.Integration.Webhook.Dedupe)
    refute Process.whereis(Jido.Integration.Dispatch.Consumer)
  end
end
