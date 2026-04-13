defmodule Jido.Integration.V2.Connectors.Notion.ClientFactoryTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.Connectors.Notion.ClientFactory
  alias Jido.Integration.V2.Connectors.Notion.Fixtures
  alias Jido.Integration.V2.Connectors.Notion.FixtureTransport

  test "builds a Notion client from the lease payload and runtime overrides only" do
    context =
      Fixtures.execution_context("notion.pages.retrieve",
        notion_client: %{
          transport: FixtureTransport,
          transport_opts: [test_pid: self()],
          auth: "shadow-token",
          notion_version: "2025-09-03",
          typed_responses: true
        }
      )

    assert {:ok, client} = ClientFactory.build(context)
    assert client.auth == Fixtures.access_token()
    assert client.transport == FixtureTransport
    assert client.transport_opts[:test_pid] == self()
    assert client.notion_version == "2025-09-03"
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
