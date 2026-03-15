defmodule Jido.Integration.V2.Connectors.GitHub.ClientFactoryTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.GitHub.ClientFactory
  alias Jido.Integration.V2.Connectors.GitHub.FixtureTransport
  alias Jido.Integration.V2.Connectors.GitHub.Fixtures

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
end
