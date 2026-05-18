defmodule Jido.Integration.V2.Auth.SecretEnvelopeTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Auth.SecretEnvelope

  setup do
    original_keyring = Application.get_env(:jido_integration_v2_auth, :keyring)
    original_runtime_env = Application.get_env(:jido_integration_v2_auth, :runtime_env)

    on_exit(fn ->
      restore_env(:keyring, original_keyring)
      restore_env(:runtime_env, original_runtime_env)
    end)

    Application.delete_env(:jido_integration_v2_auth, :keyring)
    Application.delete_env(:jido_integration_v2_auth, :runtime_env)
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
    Application.put_env(:jido_integration_v2_auth, :runtime_env, :prod)

    assert_raise ArgumentError,
                 "jido auth production configuration requires an explicit non-default keyring",
                 fn ->
                   SecretEnvelope.encrypt(%{api_key: "secret"}, "credential-ref-1")
                 end
  end

  test "allows an explicit production keyring" do
    key = Base.encode64(:crypto.hash(:sha256, "phase-five-production-key"))

    Application.put_env(:jido_integration_v2_auth, :runtime_env, :prod)

    Application.put_env(:jido_integration_v2_auth, :keyring, %{
      active_kid: "kms-prod-1",
      keys: %{"kms-prod-1" => key}
    })

    envelope = SecretEnvelope.encrypt(%{api_key: "secret"}, "credential-ref-1")

    assert envelope["kid"] == "kms-prod-1"
    assert SecretEnvelope.decrypt(envelope, "credential-ref-1") == %{api_key: "secret"}
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_integration_v2_auth, key)
  defp restore_env(key, value), do: Application.put_env(:jido_integration_v2_auth, key, value)
end
