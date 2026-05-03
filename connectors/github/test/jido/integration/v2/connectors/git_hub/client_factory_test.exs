defmodule Jido.Integration.V2.Connectors.GitHub.ClientFactoryTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Connectors.GitHub.ClientFactory
  alias Jido.Integration.V2.Connectors.GitHub.Fixtures
  alias Jido.Integration.V2.Connectors.GitHub.FixtureTransport

  test "builds a GitHubEx client from the lease payload and runtime overrides only" do
    context =
      Fixtures.execution_context("github.issue.list",
        github_client: %{
          transport: FixtureTransport,
          transport_opts: [test_pid: self()],
          base_url: "https://ghe.example.test/api/v3",
          timeout_ms: 20_000,
          auth: "shadow-token",
          typed_responses: true
        }
      )

    assert {:ok, client} = ClientFactory.build(context)
    assert client.auth == Fixtures.access_token()
    assert client.transport == FixtureTransport
    assert client.transport_opts[:test_pid] == self()
    assert client.base_url == "https://ghe.example.test/api/v3"
    assert client.timeout_ms == 20_000
    refute client.typed_responses
    assert ClientFactory.auth_binding(context) == Fixtures.auth_binding()
  end

  test "returns a stable missing token error when the lease payload has no access token" do
    assert {:error, :missing_access_token} =
             ClientFactory.build(%{
               credential_lease: %{payload: %{}},
               opts: %{}
             })
  end

  test "ignores standalone application config once a governed credential lease is present" do
    previous = Application.get_env(:jido_integration_v2_github, ClientFactory)

    Application.put_env(
      :jido_integration_v2_github,
      ClientFactory,
      base_url: "https://shadow-github-config.example.test",
      timeout_ms: 99_999
    )

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:jido_integration_v2_github, ClientFactory)
        value -> Application.put_env(:jido_integration_v2_github, ClientFactory, value)
      end
    end)

    context = Fixtures.execution_context("github.issue.list")

    assert {:ok, client} = ClientFactory.build(context)
    refute client.base_url == "https://shadow-github-config.example.test"
    refute client.timeout_ms == 99_999
    assert client.auth == Fixtures.access_token()
  end
end
