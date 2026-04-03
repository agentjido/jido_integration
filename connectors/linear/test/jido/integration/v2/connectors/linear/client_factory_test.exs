defmodule Jido.Integration.V2.Connectors.Linear.ClientFactoryTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.Linear.ClientFactory
  alias Jido.Integration.V2.Connectors.Linear.Fixtures
  alias Jido.Integration.V2.Connectors.Linear.FixtureTransport

  test "builds a LinearSDK client from an api-key lease payload and runtime overrides only" do
    context =
      Fixtures.execution_context("linear.users.get_self",
        linear_client: %{
          transport: FixtureTransport,
          base_url: "https://linear.example.test/graphql",
          headers: [{"x-test-header", "present"}],
          req_options: [receive_timeout: 15_000],
          auth: {:bearer, "shadow-token"}
        }
      )

    assert {:ok, client} = ClientFactory.build(context)
    assert client.runtime.context.auth == {:header, "Authorization", Fixtures.api_key()}
    assert client.runtime.context.transport == FixtureTransport
    assert client.runtime.context.base_url == "https://linear.example.test/graphql"
    assert client.runtime.context.headers == [{"x-test-header", "present"}]
    assert client.runtime.context.req_options == [receive_timeout: 15_000]
    assert ClientFactory.auth_binding(context) == Fixtures.auth_binding()
  end

  test "builds a LinearSDK client from an oauth lease payload" do
    context = %{
      credential_lease: Fixtures.oauth_credential_lease(),
      opts: %{linear_client: [transport: FixtureTransport]}
    }

    assert {:ok, client} = ClientFactory.build(context)
    assert client.runtime.context.auth == {:bearer, Fixtures.oauth_access_token()}
    assert client.runtime.context.transport == FixtureTransport

    assert ClientFactory.auth_binding(context) ==
             Fixtures.auth_binding(Fixtures.oauth_access_token())
  end

  test "returns a stable missing-auth error when the lease payload has no api key or access token" do
    assert {:error, :missing_runtime_auth} =
             ClientFactory.build(%{
               credential_lease: %{payload: %{}},
               opts: %{}
             })
  end

  test "ignores configured and runtime oauth2 sources so invoke stays lease-bound" do
    previous_config =
      Application.get_env(:jido_integration_v2_linear, ClientFactory, [])

    Application.put_env(
      :jido_integration_v2_linear,
      ClientFactory,
      oauth2: [token_source: {:static, %{access_token: "shadow-config-token"}}]
    )

    on_exit(fn ->
      case previous_config do
        nil -> Application.delete_env(:jido_integration_v2_linear, ClientFactory)
        value -> Application.put_env(:jido_integration_v2_linear, ClientFactory, value)
      end
    end)

    context =
      Fixtures.execution_context("linear.users.get_self",
        linear_client: %{
          oauth2: [token_source: {:static, %{access_token: "shadow-runtime-token"}}],
          transport: FixtureTransport
        }
      )

    assert {:ok, client} = ClientFactory.build(context)
    assert client.runtime.context.auth == {:header, "Authorization", Fixtures.api_key()}
    assert client.runtime.context.oauth2 == nil
  end
end
