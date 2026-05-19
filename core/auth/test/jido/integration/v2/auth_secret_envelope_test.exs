defmodule Jido.Integration.V2.Auth.SecretEnvelopeTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Auth.RuntimeConfig
  alias Jido.Integration.V2.Auth.SecretEnvelope

  setup do
    original_runtime_config = RuntimeConfig.current()
    :ok = RuntimeConfig.reset()

    on_exit(fn ->
      :ok = RuntimeConfig.reset()
      restore_runtime_config(original_runtime_config)
    end)

    :ok
  end

  test "uses an explicit JSON envelope and preserves known atom secret keys" do
    envelope =
      SecretEnvelope.encrypt(
        %{access_token: "secret-token"} |> Map.put("api_key", "linear-secret"),
        "credential-ref-1"
      )

    assert envelope["format"] == "json-v1"
    assert envelope["ciphertext"]
    refute inspect(envelope) =~ "secret-token"
    refute inspect(envelope) =~ "linear-secret"

    expected = %{access_token: "secret-token"} |> Map.put("api_key", "linear-secret")

    assert SecretEnvelope.decrypt(envelope, "credential-ref-1") == expected
  end

  test "rejects the dev default keyring in production configuration" do
    :ok = RuntimeConfig.put(:runtime_env, :prod)

    assert_raise ArgumentError,
                 "jido auth production configuration requires an explicit non-default keyring",
                 fn ->
                   SecretEnvelope.encrypt(%{api_key: "secret"}, "credential-ref-1")
                 end
  end

  test "allows an explicit production keyring" do
    key = Base.encode64(:crypto.hash(:sha256, "phase-five-production-key"))

    :ok = RuntimeConfig.put(:runtime_env, :prod)

    :ok =
      RuntimeConfig.put(:keyring, %{
        active_kid: "kms-prod-1",
        keys: %{"kms-prod-1" => key}
      })

    envelope = SecretEnvelope.encrypt(%{api_key: "secret"}, "credential-ref-1")

    assert envelope["kid"] == "kms-prod-1"
    assert SecretEnvelope.decrypt(envelope, "credential-ref-1") == %{api_key: "secret"}
  end

  defp restore_runtime_config(config) do
    Enum.each(config, fn {key, value} ->
      :ok = RuntimeConfig.put(key, value)
    end)
  end
end
