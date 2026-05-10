defmodule Jido.Integration.ToolchainTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.Toolchain

  test "configured mix executable comes from materialized application env" do
    previous_env = Application.get_env(:jido_integration_workspace, :env)
    configured = Path.join(System.tmp_dir!(), "jido-configured-mix")

    Application.put_env(:jido_integration_workspace, :env, %{
      "JIDO_INTEGRATION_MIX_EXECUTABLE" => configured
    })

    try do
      assert Toolchain.mix_executable() == configured
    after
      case previous_env do
        nil -> Application.delete_env(:jido_integration_workspace, :env)
        value -> Application.put_env(:jido_integration_workspace, :env, value)
      end
    end
  end
end
