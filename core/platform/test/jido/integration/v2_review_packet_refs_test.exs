defmodule Jido.Integration.V2ReviewPacketRefsTest do
  use Jido.Integration.V2.ConnectorContractCase, async: false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.GitHub.ClientFactory
  alias Jido.Integration.V2.Connectors.GitHub.Fixtures, as: GitHubFixtures

  @github %{
    connector: GitHub,
    connector_id: "github",
    tenant_id: "tenant-github-review-refs",
    environment: :prod
  }

  @github_create_spec %{
    capability_id: "github.issue.create",
    tenant_id: @github.tenant_id,
    environment: @github.environment,
    sandbox: %{
      level: :standard,
      egress: :restricted,
      approvals: :auto,
      allowed_tools: ["github.api.issue.create"]
    }
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

  test "review_packet exposes stable packet metadata refs over durable truth" do
    register_connector!(@github.connector)

    connection_id =
      install_connection!(
        @github.connector_id,
        @github.tenant_id,
        "review-ref-operator",
        ["repo"],
        %{access_token: "gho_review_ref"}
      )

    assert {:ok, result} =
             V2.invoke(
               "github.issue.create",
               %{
                 repo: "agentjido/jido_integration_v2",
                 title: "Review packet refs",
                 body: "Prove stable packet refs"
               },
               invoke_opts("github.issue.create", connection_id, @github_create_spec)
             )

    assert {:ok, packet} =
             V2.review_packet(result.run.run_id, %{attempt_id: result.attempt.attempt_id})

    assert packet.metadata.packet_ref ==
             "jido://v2/review_packet/run/#{result.run.run_id}?attempt_id=#{URI.encode_www_form(result.attempt.attempt_id)}"

    assert packet.metadata.projection == "operator.review_packet"

    assert packet.metadata.subject == %{
             ref: "jido://v2/subject/run/#{result.run.run_id}",
             kind: :run,
             id: result.run.run_id,
             metadata: %{}
           }

    assert packet.metadata.selected_attempt == %{
             ref: "jido://v2/subject/attempt/#{URI.encode_www_form(result.attempt.attempt_id)}",
             kind: :attempt,
             id: result.attempt.attempt_id,
             metadata: %{attempt: result.attempt.attempt, run_id: result.run.run_id}
           }

    assert Enum.any?(packet.metadata.evidence_refs, fn evidence_ref ->
             evidence_ref == %{
               ref: "jido://v2/evidence/run/#{result.run.run_id}",
               kind: :run,
               id: result.run.run_id,
               packet_ref: packet.metadata.packet_ref,
               subject: packet.metadata.subject,
               metadata: %{status: :completed}
             }
           end)

    assert Enum.any?(packet.metadata.evidence_refs, fn evidence_ref ->
             evidence_ref.kind == :connection and
               evidence_ref.id == connection_id and
               evidence_ref.metadata.connector_id == "github"
           end)

    assert Enum.any?(packet.metadata.evidence_refs, fn evidence_ref ->
             evidence_ref.kind == :install and
               evidence_ref.id == packet.install.install_id and
               evidence_ref.metadata.connection_id == connection_id
           end)

    assert packet.metadata.governance_refs == []
    assert Jason.encode!(packet.metadata)
  end

  test "review_packet surfaces governance refs from durable policy-denial events" do
    register_connector!(@github.connector)

    connection_id =
      install_connection!(
        @github.connector_id,
        @github.tenant_id,
        "review-ref-readonly",
        ["issues:read"],
        %{access_token: "gho_review_ref_denied"}
      )

    assert {:error, error} =
             V2.invoke(
               "github.issue.create",
               %{repo: "agentjido/jido_integration_v2", title: "Denied"},
               invoke_opts("github.issue.create", connection_id, @github_create_spec)
             )

    assert {:ok, packet} = V2.review_packet(error.run.run_id)
    assert [governance_ref] = packet.metadata.governance_refs

    assert governance_ref.kind == :policy_decision
    assert governance_ref.subject == packet.metadata.subject
    assert governance_ref.metadata.status == :denied
    assert governance_ref.metadata.event_type == "audit.policy_denied"

    assert Enum.any?(governance_ref.evidence, fn evidence_ref ->
             evidence_ref.kind == :event and evidence_ref.metadata.type == "audit.policy_denied"
           end)
  end
end
