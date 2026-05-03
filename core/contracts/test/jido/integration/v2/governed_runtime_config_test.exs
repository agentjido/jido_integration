defmodule Jido.Integration.V2.GovernedRuntimeConfigTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.GovernedRuntimeConfig

  @app :jido_integration_contracts
  @key __MODULE__

  setup do
    previous = Application.get_env(@app, @key)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(@app, @key)
        value -> Application.put_env(@app, @key, value)
      end
    end)

    :ok
  end

  test "governed contexts ignore standalone application options" do
    Application.put_env(@app, @key, base_url: "https://shadow.example.test", timeout_ms: 9)

    opts =
      GovernedRuntimeConfig.standalone_application_opts(
        %{credential_lease: %{payload: %{access_token: "lease-token"}}},
        @app,
        @key,
        [:base_url, :timeout_ms]
      )

    assert opts == []
  end

  test "standalone contexts keep application options for compatibility" do
    Application.put_env(@app, @key, base_url: "https://standalone.example.test", ignored: true)

    assert GovernedRuntimeConfig.standalone_application_opts(%{}, @app, @key, [
             :base_url,
             :timeout_ms
           ]) == [base_url: "https://standalone.example.test"]
  end
end
