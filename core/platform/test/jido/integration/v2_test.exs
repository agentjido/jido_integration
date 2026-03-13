defmodule Jido.Integration.V2Test do
  use Jido.Integration.V2.ConnectorContractCase

  alias Jido.Integration.V2.Connectors.CodexCli
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.InvocationRequest
  alias Jido.Integration.V2.Connectors.MarketData

  @github %{
    connector: GitHub,
    connector_id: "github",
    capability_id: "github.issue.create",
    tenant_id: "tenant-github",
    environment: :prod,
    sandbox: %{
      level: :standard,
      egress: :restricted,
      approvals: :auto,
      allowed_tools: ["github.api.issue.create"]
    },
    event_type: "connector.github.issue.created",
    artifact_type: :tool_output
  }

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

  test "registers connectors and exposes direct, session, and stream capabilities" do
    register_connector!(@github.connector)
    register_connector!(@codex_cli.connector)
    register_connector!(@market_data.connector)

    capability_ids =
      V2.capabilities()
      |> Enum.map(&{&1.id, &1.runtime_class})
      |> Enum.sort()

    assert {"codex.exec.session", :session} in capability_ids
    assert {"github.issue.create", :direct} in capability_ids
    assert {"market.ticks.pull", :stream} in capability_ids
  end

  test "lists connectors and fetches connector and capability discovery records" do
    register_connector!(@market_data.connector)
    register_connector!(@github.connector)
    register_connector!(@codex_cli.connector)

    assert Enum.map(V2.connectors(), & &1.connector) == ["codex_cli", "github", "market_data"]

    assert {:ok, github_manifest} = V2.fetch_connector("github")
    assert github_manifest.connector == "github"
    assert Enum.map(github_manifest.capabilities, & &1.id) == ["github.issue.create"]
    assert {:error, :unknown_connector} = V2.fetch_connector("missing")

    assert {:ok, capability} = V2.fetch_capability("github.issue.create")
    assert capability.connector == "github"
    assert capability.runtime_class == :direct
    assert {:error, :unknown_capability} = V2.fetch_capability("github.issue.close")
  end

  test "invoke/1 accepts an invocation request and matches invoke/3 behavior" do
    register_connector!(@github.connector)

    credential_ref =
      install_connection!(
        @github.connector_id,
        @github.tenant_id,
        "octocat",
        ["repo"],
        %{access_token: "gho_test", refresh_token: "ghr_test"}
      )

    request =
      InvocationRequest.new!(%{
        capability_id: @github.capability_id,
        input: %{
          repo: "agentjido/jido_integration_v2",
          title: "Ship the platform package"
        },
        credential_ref: credential_ref,
        actor_id: "connector-contract",
        tenant_id: @github.tenant_id,
        environment: @github.environment,
        sandbox: @github.sandbox
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

  test "direct connector emits reviewable events and durable artifacts through a lease" do
    register_connector!(@github.connector)

    credential_ref =
      install_connection!(
        @github.connector_id,
        @github.tenant_id,
        "octocat",
        ["repo"],
        %{access_token: "gho_test", refresh_token: "ghr_test"}
      )

    assert {:ok, result} =
             V2.invoke(
               @github.capability_id,
               %{repo: "agentjido/jido_integration_v2", title: "Ship the platform package"},
               invoke_opts(@github.capability_id, credential_ref, @github)
             )

    assert result.run.runtime_class == :direct
    assert result.attempt.status == :completed
    assert result.attempt.runtime_ref_id == nil
    assert result.output.opened_by == "octocat"
    assert result.output.auth_binding =~ "sha256:"

    assert_review_surface!(
      result,
      @github,
      %{access_token: "gho_test"},
      ["gho_test", "ghr_test"]
    )
  end

  test "direct connector denies work when the credential scopes are insufficient" do
    register_connector!(@github.connector)

    credential_ref =
      install_connection!(
        @github.connector_id,
        @github.tenant_id,
        "readonly-octocat",
        ["issues:read"],
        %{access_token: "gho_readonly"}
      )

    assert {:error, error} =
             V2.invoke(
               @github.capability_id,
               %{repo: "agentjido/jido_integration_v2", title: "Denied"},
               invoke_opts(@github.capability_id, credential_ref, @github)
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

  test "session connector reuses the runtime for the same credential and persists review artifacts" do
    register_connector!(@codex_cli.connector)

    credential_ref =
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
               invoke_opts(@codex_cli.capability_id, credential_ref, @codex_cli)
             )

    assert {:ok, second} =
             V2.invoke(
               @codex_cli.capability_id,
               %{prompt: "Now turn it into a checklist"},
               invoke_opts(@codex_cli.capability_id, credential_ref, @codex_cli)
             )

    assert first.run.runtime_class == :session
    assert first.attempt.runtime_ref_id == second.attempt.runtime_ref_id
    assert first.output.turn == 1
    assert second.output.turn == 2
    assert second.output.workspace == "/workspaces/codex_cli"
    assert second.output.approval_mode == :manual

    assert_review_surface!(first, @codex_cli, %{access_token: "codex_test"}, ["codex_test"])
    assert_review_surface!(second, @codex_cli, %{access_token: "codex_test"}, ["codex_test"])
  end

  test "session connector does not reuse a runtime across different credential refs for the same subject" do
    register_connector!(@codex_cli.connector)

    first_credential =
      install_connection!(
        @codex_cli.connector_id,
        @codex_cli.tenant_id,
        "shared-subject",
        ["session:execute"],
        %{access_token: "codex_a"}
      )

    second_credential =
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
               invoke_opts(@codex_cli.capability_id, first_credential, @codex_cli)
             )

    assert {:ok, second} =
             V2.invoke(
               @codex_cli.capability_id,
               %{prompt: "Summarize risk"},
               invoke_opts(@codex_cli.capability_id, second_credential, @codex_cli)
             )

    refute first.attempt.runtime_ref_id == second.attempt.runtime_ref_id
  end

  test "session connector denies work when sandbox policy is weaker than required" do
    register_connector!(@codex_cli.connector)

    credential_ref =
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
                 credential_ref,
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

  test "stream connector reuses stream state per credential and symbol" do
    register_connector!(@market_data.connector)

    credential_ref =
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
               invoke_opts(@market_data.capability_id, credential_ref, @market_data)
             )

    assert {:ok, second} =
             V2.invoke(
               @market_data.capability_id,
               %{symbol: "ES", limit: 2, venue: "CME"},
               invoke_opts(@market_data.capability_id, credential_ref, @market_data)
             )

    assert first.run.runtime_class == :stream
    assert first.attempt.runtime_ref_id == second.attempt.runtime_ref_id
    assert first.output.cursor == 2
    assert second.output.cursor == 4
    assert Enum.map(first.output.items, & &1.seq) == [1, 2]
    assert Enum.map(second.output.items, & &1.seq) == [3, 4]
    assert Enum.all?(second.output.items, &(&1.venue == "CME"))

    assert_review_surface!(first, @market_data, %{api_key: "market_demo"}, ["market_demo"])
  end

  test "stream connector does not reuse stream state across different credential refs for the same subject" do
    register_connector!(@market_data.connector)

    first_credential =
      install_connection!(
        @market_data.connector_id,
        @market_data.tenant_id,
        "shared-stream-subject",
        ["market:read"],
        %{api_key: "market_a"}
      )

    second_credential =
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
               invoke_opts(@market_data.capability_id, first_credential, @market_data)
             )

    assert {:ok, second} =
             V2.invoke(
               @market_data.capability_id,
               %{symbol: "ES", limit: 1},
               invoke_opts(@market_data.capability_id, second_credential, @market_data)
             )

    refute first.attempt.runtime_ref_id == second.attempt.runtime_ref_id
  end

  test "stream connector denies work outside its allowed environment" do
    register_connector!(@market_data.connector)

    credential_ref =
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
                 credential_ref,
                 @market_data,
                 environment: :dev
               )
             )

    assert error.reason == :policy_denied

    assert "environment dev is not permitted for market.ticks.pull" in error.policy_decision.reasons
  end
end
