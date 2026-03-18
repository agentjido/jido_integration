defmodule Jido.Integration.V2Test do
  use Jido.Integration.V2.ConnectorContractCase, async: false

  alias Jido.Integration.V2.Connectors.CodexCli
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.GitHub.ClientFactory
  alias Jido.Integration.V2.Connectors.GitHub.Fixtures, as: GitHubFixtures
  alias Jido.Integration.V2.Connectors.MarketData
  alias Jido.Integration.V2.InvocationRequest

  @github %{
    connector: GitHub,
    connector_id: "github",
    tenant_id: "tenant-github",
    environment: :prod,
    artifact_type: :tool_output
  }

  @github_capabilities [
    %{
      capability_id: "github.comment.create",
      event_type: "connector.github.comment.created",
      allowed_tools: ["github.api.comment.create"],
      artifact_slug: "comment_create",
      input: %{
        repo: "agentjido/jido_integration_v2",
        issue_number: 42,
        body: "Add a deterministic review note"
      }
    },
    %{
      capability_id: "github.comment.update",
      event_type: "connector.github.comment.updated",
      allowed_tools: ["github.api.comment.update"],
      artifact_slug: "comment_update",
      input: %{
        repo: "agentjido/jido_integration_v2",
        comment_id: 901,
        body: "Edited deterministic review note"
      }
    },
    %{
      capability_id: "github.issue.close",
      event_type: "connector.github.issue.closed",
      allowed_tools: ["github.api.issue.close"],
      artifact_slug: "issue_close",
      input: %{repo: "agentjido/jido_integration_v2", issue_number: 42}
    },
    %{
      capability_id: "github.issue.create",
      event_type: "connector.github.issue.created",
      allowed_tools: ["github.api.issue.create"],
      artifact_slug: "issue_create",
      input: %{
        repo: "agentjido/jido_integration_v2",
        title: "Ship the platform package",
        body: "Direct runtime slice"
      }
    },
    %{
      capability_id: "github.issue.fetch",
      event_type: "connector.github.issue.fetched",
      allowed_tools: ["github.api.issue.fetch"],
      artifact_slug: "issue_fetch",
      input: %{repo: "agentjido/jido_integration_v2", issue_number: 42}
    },
    %{
      capability_id: "github.issue.label",
      event_type: "connector.github.issue.labeled",
      allowed_tools: ["github.api.issue.label"],
      artifact_slug: "issue_label",
      input: %{
        repo: "agentjido/jido_integration_v2",
        issue_number: 42,
        labels: ["platform", "triaged"]
      }
    },
    %{
      capability_id: "github.issue.list",
      event_type: "connector.github.issue.listed",
      allowed_tools: ["github.api.issue.list"],
      artifact_slug: "issue_list",
      input: %{repo: "agentjido/jido_integration_v2", state: "open", per_page: 2, page: 1}
    },
    %{
      capability_id: "github.issue.update",
      event_type: "connector.github.issue.updated",
      allowed_tools: ["github.api.issue.update"],
      artifact_slug: "issue_update",
      input: %{
        repo: "agentjido/jido_integration_v2",
        issue_number: 42,
        title: "Ship the platform package now",
        body: "Expanded deterministic review surface",
        state: "open",
        labels: ["platform", "v2"],
        assignees: ["octocat"]
      }
    }
  ]

  @github_capability_ids Enum.map(@github_capabilities, & &1.capability_id)
  @github_capability_specs Map.new(@github_capabilities, &{&1.capability_id, &1})

  @codex_cli %{
    connector: CodexCli,
    connector_id: "codex_cli",
    capability_id: "codex.exec.session",
    tenant_id: "tenant-codex",
    environment: :prod,
    sandbox: %{
      level: :strict,
      egress: :restricted,
      approvals: :manual,
      file_scope: "/workspaces/codex_cli",
      allowed_tools: ["codex.exec.session"]
    },
    event_type: "connector.codex_cli.turn.completed",
    artifact_type: :event_log
  }

  @market_data %{
    connector: MarketData,
    connector_id: "market_data",
    capability_id: "market.ticks.pull",
    tenant_id: "tenant-market",
    environment: :prod,
    sandbox: %{
      level: :standard,
      egress: :blocked,
      approvals: :auto,
      allowed_tools: ["market.feed.pull"]
    },
    event_type: "connector.market_data.batch.pulled",
    artifact_type: :log
  }

  setup do
    previous = Application.get_env(:jido_integration_v2_github, ClientFactory)

    Application.put_env(
      :jido_integration_v2_github,
      ClientFactory,
      GitHubFixtures.client_opts(nil)
    )

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:jido_integration_v2_github, ClientFactory)
      else
        Application.put_env(:jido_integration_v2_github, ClientFactory, previous)
      end
    end)

    :ok
  end

  test "registers connectors and exposes direct, session, and stream capabilities" do
    register_connector!(@github.connector)
    register_connector!(@codex_cli.connector)
    register_connector!(@market_data.connector)

    capability_ids =
      V2.capabilities()
      |> Enum.map(&{&1.id, &1.runtime_class})
      |> Enum.sort()

    assert {"codex.exec.session", :session} in capability_ids

    Enum.each(@github_capability_ids, fn capability_id ->
      assert {capability_id, :direct} in capability_ids
    end)

    assert {"market.ticks.pull", :stream} in capability_ids
  end

  test "lists connectors and fetches connector and capability discovery records" do
    register_connector!(@market_data.connector)
    register_connector!(@github.connector)
    register_connector!(@codex_cli.connector)

    assert Enum.map(V2.connectors(), & &1.connector) == ["codex_cli", "github", "market_data"]

    assert {:ok, github_manifest} = V2.fetch_connector("github")
    assert github_manifest.connector == "github"
    assert Enum.map(github_manifest.capabilities, & &1.id) == @github_capability_ids
    assert {:error, :unknown_connector} = V2.fetch_connector("missing")

    assert {:ok, capability} = V2.fetch_capability("github.issue.create")
    assert capability.connector == "github"
    assert capability.runtime_class == :direct
    assert {:ok, closed_issue} = V2.fetch_capability("github.issue.close")
    assert closed_issue.metadata.policy.sandbox.allowed_tools == ["github.api.issue.close"]
    assert {:error, :unknown_capability} = V2.fetch_capability("github.issue.reopen")
  end

  test "invoke/1 accepts an invocation request and matches invoke/3 behavior" do
    register_connector!(@github.connector)
    github_spec = github_spec("github.issue.create")

    connection_id =
      install_connection!(
        @github.connector_id,
        @github.tenant_id,
        "octocat",
        ["repo"],
        %{access_token: "gho_test", refresh_token: "ghr_test"}
      )

    request =
      InvocationRequest.new!(%{
        capability_id: "github.issue.create",
        connection_id: connection_id,
        input: %{
          repo: "agentjido/jido_integration_v2",
          title: "Ship the platform package",
          body: "Direct runtime slice"
        },
        actor_id: "connector-contract",
        tenant_id: @github.tenant_id,
        environment: @github.environment,
        sandbox: github_spec.sandbox
      })

    assert {:ok, via_request} = V2.invoke(request)

    assert {:ok, via_arity_three} =
             V2.invoke(request.capability_id, request.input, InvocationRequest.to_opts(request))

    assert via_request.output == via_arity_three.output
    assert via_request.run.capability_id == via_arity_three.run.capability_id
    assert via_request.run.runtime_class == via_arity_three.run.runtime_class
    assert via_request.run.status == via_arity_three.run.status
    assert via_request.attempt.status == via_arity_three.attempt.status
    assert via_request.attempt.runtime_ref_id == via_arity_three.attempt.runtime_ref_id
  end

  test "direct GitHub capabilities emit reviewable events and durable artifacts through a lease" do
    register_connector!(@github.connector)

    connection_id =
      install_connection!(
        @github.connector_id,
        @github.tenant_id,
        "octocat",
        ["repo"],
        %{access_token: "gho_test", refresh_token: "ghr_test"}
      )

    Enum.each(@github_capabilities, fn capability_spec ->
      spec = github_spec(capability_spec.capability_id)

      assert {:ok, result} =
               V2.invoke(
                 capability_spec.capability_id,
                 capability_spec.input,
                 invoke_opts(capability_spec.capability_id, connection_id, spec)
               )

      assert result.run.runtime_class == :direct
      assert result.attempt.status == :completed
      assert result.attempt.runtime_ref_id == nil
      assert result.output.auth_binding =~ "sha256:"

      assert_github_output(capability_spec.capability_id, capability_spec.input, result.output)

      assert [artifact] = V2.run_artifacts(result.run.run_id)

      assert artifact.payload_ref.key ==
               github_artifact_key(
                 capability_spec.capability_id,
                 capability_spec.artifact_slug,
                 result.run.run_id,
                 result.attempt.attempt_id
               )

      assert_review_surface!(
        result,
        spec,
        %{access_token: "gho_test"},
        ["gho_test", "ghr_test"]
      )
    end)
  end

  test "direct connector denies work when the credential scopes are insufficient" do
    register_connector!(@github.connector)
    github_spec = github_spec("github.issue.create")

    connection_id =
      install_connection!(
        @github.connector_id,
        @github.tenant_id,
        "readonly-octocat",
        ["issues:read"],
        %{access_token: "gho_readonly"}
      )

    assert {:error, error} =
             V2.invoke(
               "github.issue.create",
               %{repo: "agentjido/jido_integration_v2", title: "Denied"},
               invoke_opts("github.issue.create", connection_id, github_spec)
             )

    assert error.reason == :policy_denied
    assert error.run.status == :denied
    assert error.attempt == nil
    assert "missing required scopes: repo" in error.policy_decision.reasons

    assert Enum.map(V2.events(error.run.run_id), & &1.type) == [
             "run.denied",
             "audit.policy_denied"
           ]
  end

  test "invoke requires connection_id for auth-scoped capabilities" do
    register_connector!(@github.connector)
    github_spec = github_spec("github.issue.create")

    assert {:error, :connection_required} =
             V2.invoke(
               "github.issue.create",
               %{repo: "agentjido/jido_integration_v2", title: "Denied"},
               Keyword.drop(
                 invoke_opts("github.issue.create", "connection-unused", github_spec),
                 [:connection_id]
               )
             )
  end

  test "session connector reuses the runtime for the same connection and persists review artifacts" do
    register_connector!(@codex_cli.connector)

    connection_id =
      install_connection!(
        @codex_cli.connector_id,
        @codex_cli.tenant_id,
        "trader-ops",
        ["session:execute"],
        %{access_token: "codex_test"}
      )

    assert {:ok, first} =
             V2.invoke(
               @codex_cli.capability_id,
               %{prompt: "Draft a calmer stop-loss summary"},
               invoke_opts(@codex_cli.capability_id, connection_id, @codex_cli)
             )

    assert {:ok, second} =
             V2.invoke(
               @codex_cli.capability_id,
               %{prompt: "Now turn it into a checklist"},
               invoke_opts(@codex_cli.capability_id, connection_id, @codex_cli)
             )

    assert first.run.runtime_class == :session
    assert first.attempt.runtime_ref_id == second.attempt.runtime_ref_id
    assert first.output.turn == 1
    assert second.output.turn == 2
    assert second.output.workspace == "/workspaces/codex_cli"
    assert second.output.approval_mode == :manual

    assert Enum.any?(V2.events(second.run.run_id), fn event ->
             event.session_id == second.attempt.runtime_ref_id and
               event.runtime_ref_id == second.attempt.runtime_ref_id
           end)

    assert_review_surface!(first, @codex_cli, %{access_token: "codex_test"}, ["codex_test"])
    assert_review_surface!(second, @codex_cli, %{access_token: "codex_test"}, ["codex_test"])
  end

  test "session connector does not reuse a runtime across different connections for the same subject" do
    register_connector!(@codex_cli.connector)

    first_connection_id =
      install_connection!(
        @codex_cli.connector_id,
        @codex_cli.tenant_id,
        "shared-subject",
        ["session:execute"],
        %{access_token: "codex_a"}
      )

    second_connection_id =
      install_connection!(
        @codex_cli.connector_id,
        @codex_cli.tenant_id,
        "shared-subject",
        ["session:execute"],
        %{access_token: "codex_b"}
      )

    assert {:ok, first} =
             V2.invoke(
               @codex_cli.capability_id,
               %{prompt: "Summarize risk"},
               invoke_opts(@codex_cli.capability_id, first_connection_id, @codex_cli)
             )

    assert {:ok, second} =
             V2.invoke(
               @codex_cli.capability_id,
               %{prompt: "Summarize risk"},
               invoke_opts(@codex_cli.capability_id, second_connection_id, @codex_cli)
             )

    refute first.attempt.runtime_ref_id == second.attempt.runtime_ref_id
  end

  test "session connector denies work when sandbox policy is weaker than required" do
    register_connector!(@codex_cli.connector)

    connection_id =
      install_connection!(
        @codex_cli.connector_id,
        @codex_cli.tenant_id,
        "sandbox-check",
        ["session:execute"],
        %{access_token: "codex_denied"}
      )

    assert {:error, error} =
             V2.invoke(
               @codex_cli.capability_id,
               %{prompt: "Denied"},
               invoke_opts(
                 @codex_cli.capability_id,
                 connection_id,
                 @codex_cli,
                 sandbox: %{
                   level: :standard,
                   egress: :restricted,
                   approvals: :auto,
                   allowed_tools: []
                 }
               )
             )

    assert error.reason == :policy_denied

    assert "sandbox level standard is weaker than required strict" in error.policy_decision.reasons

    assert "sandbox tool allowlist is missing: codex.exec.session" in error.policy_decision.reasons
  end

  test "stream connector reuses stream state per connection and symbol" do
    register_connector!(@market_data.connector)

    connection_id =
      install_connection!(
        @market_data.connector_id,
        @market_data.tenant_id,
        "desk-stream",
        ["market:read"],
        %{api_key: "market_demo"}
      )

    assert {:ok, first} =
             V2.invoke(
               @market_data.capability_id,
               %{symbol: "ES", limit: 2, venue: "CME"},
               invoke_opts(@market_data.capability_id, connection_id, @market_data)
             )

    assert {:ok, second} =
             V2.invoke(
               @market_data.capability_id,
               %{symbol: "ES", limit: 2, venue: "CME"},
               invoke_opts(@market_data.capability_id, connection_id, @market_data)
             )

    assert first.run.runtime_class == :stream
    assert first.attempt.runtime_ref_id == second.attempt.runtime_ref_id
    assert first.output.cursor == 2
    assert second.output.cursor == 4
    assert Enum.map(first.output.items, & &1.seq) == [1, 2]
    assert Enum.map(second.output.items, & &1.seq) == [3, 4]
    assert Enum.all?(second.output.items, &(&1.venue == "CME"))

    assert Enum.any?(V2.events(second.run.run_id), fn event ->
             event.session_id == second.attempt.runtime_ref_id and
               event.runtime_ref_id == second.attempt.runtime_ref_id
           end)

    assert_review_surface!(first, @market_data, %{api_key: "market_demo"}, ["market_demo"])
  end

  test "stream connector does not reuse stream state across different connections for the same subject" do
    register_connector!(@market_data.connector)

    first_connection_id =
      install_connection!(
        @market_data.connector_id,
        @market_data.tenant_id,
        "shared-stream-subject",
        ["market:read"],
        %{api_key: "market_a"}
      )

    second_connection_id =
      install_connection!(
        @market_data.connector_id,
        @market_data.tenant_id,
        "shared-stream-subject",
        ["market:read"],
        %{api_key: "market_b"}
      )

    assert {:ok, first} =
             V2.invoke(
               @market_data.capability_id,
               %{symbol: "ES", limit: 1},
               invoke_opts(@market_data.capability_id, first_connection_id, @market_data)
             )

    assert {:ok, second} =
             V2.invoke(
               @market_data.capability_id,
               %{symbol: "ES", limit: 1},
               invoke_opts(@market_data.capability_id, second_connection_id, @market_data)
             )

    refute first.attempt.runtime_ref_id == second.attempt.runtime_ref_id
  end

  test "stream connector denies work outside its allowed environment" do
    register_connector!(@market_data.connector)

    connection_id =
      install_connection!(
        @market_data.connector_id,
        @market_data.tenant_id,
        "env-check",
        ["market:read"],
        %{api_key: "market_env"}
      )

    assert {:error, error} =
             V2.invoke(
               @market_data.capability_id,
               %{symbol: "ES", limit: 1},
               invoke_opts(
                 @market_data.capability_id,
                 connection_id,
                 @market_data,
                 environment: :dev
               )
             )

    assert error.reason == :policy_denied

    assert "environment dev is not permitted for market.ticks.pull" in error.policy_decision.reasons
  end

  defp github_spec(capability_id) do
    capability = Map.fetch!(@github_capability_specs, capability_id)

    Map.merge(
      @github,
      %{
        capability_id: capability_id,
        event_type: capability.event_type,
        sandbox: %{
          level: :standard,
          egress: :restricted,
          approvals: :auto,
          allowed_tools: capability.allowed_tools
        }
      }
    )
  end

  defp github_artifact_key(_capability_id, artifact_slug, run_id, attempt_id) do
    "github/#{run_id}/#{attempt_id}/#{artifact_slug}.term"
  end

  defp assert_github_output("github.issue.list", input, output) do
    assert output.repo == input.repo
    assert output.state == input.state
    assert output.page == input.page
    assert output.per_page == input.per_page
    assert output.total_count == length(output.issues)
    assert length(output.issues) == input.per_page
    assert output.listed_by == "octocat"
  end

  defp assert_github_output("github.issue.fetch", input, output) do
    assert output.repo == input.repo
    assert output.issue_number == input.issue_number
    assert output.fetched_by == "octocat"
    assert output.state in ["open", "closed"]
    assert is_binary(output.title)
    assert is_binary(output.body)
  end

  defp assert_github_output("github.issue.create", input, output) do
    assert output.repo == input.repo
    assert output.title == input.title
    assert output.body == input.body
    assert output.state == "open"
    assert output.opened_by == "octocat"
    assert is_integer(output.issue_number)
  end

  defp assert_github_output("github.issue.update", input, output) do
    assert output.repo == input.repo
    assert output.issue_number == input.issue_number
    assert output.title == input.title
    assert output.body == input.body
    assert output.state == input.state
    assert output.labels == input.labels
    assert output.assignees == input.assignees
    assert output.updated_by == "octocat"
  end

  defp assert_github_output("github.issue.label", input, output) do
    assert output.repo == input.repo
    assert output.issue_number == input.issue_number
    assert output.labels == input.labels
    assert output.labeled_by == "octocat"
  end

  defp assert_github_output("github.issue.close", input, output) do
    assert output.repo == input.repo
    assert output.issue_number == input.issue_number
    assert output.state == "closed"
    assert output.closed_by == "octocat"
  end

  defp assert_github_output("github.comment.create", input, output) do
    assert output.repo == input.repo
    assert output.issue_number == input.issue_number
    assert output.body == input.body
    assert output.created_by == "octocat"
    assert is_integer(output.comment_id)
  end

  defp assert_github_output("github.comment.update", input, output) do
    assert output.repo == input.repo
    assert output.comment_id == input.comment_id
    assert output.body == input.body
    assert output.updated_by == "octocat"
  end
end
