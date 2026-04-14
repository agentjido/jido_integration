defmodule Jido.Integration.V2DerivedStateAttachmentTest do
  use Jido.Integration.V2.ConnectorContractCase, async: false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.GitHub.ClientFactory
  alias Jido.Integration.V2.Connectors.GitHub.Fixtures, as: GitHubFixtures
  alias Jido.Integration.V2.DerivedStateAttachment

  @github %{
    connector: GitHub,
    connector_id: "github",
    tenant_id: "tenant-github-derived-attachment",
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

  test "derived_state_attachment/2 exposes stable subject, evidence, and governance refs" do
    register_connector!(@github.connector)

    connection_id =
      install_connection!(
        @github.connector_id,
        @github.tenant_id,
        "derived-state-operator",
        ["repo"],
        %{access_token: "gho_derived_state"}
      )

    assert {:ok, result} =
             V2.invoke(
               "github.issue.create",
               %{
                 repo: "agentjido/jido_integration_v2",
                 title: "Derived attachment",
                 body: "Prove stable attachment refs"
               },
               invoke_opts("github.issue.create", connection_id, @github_create_spec)
             )

    assert {:ok, %DerivedStateAttachment{} = attachment} =
             V2.derived_state_attachment(result.run.run_id, %{
               attempt_id: result.attempt.attempt_id
             })

    assert attachment.subject.ref == "jido://v2/subject/run/#{result.run.run_id}"
    assert attachment.subject.kind == :run
    assert attachment.subject.id == result.run.run_id
    assert attachment.metadata.source_projection == "operator.derived_state_attachment"

    assert Enum.any?(attachment.evidence_refs, fn evidence_ref ->
             evidence_ref.kind == :run and
               evidence_ref.id == result.run.run_id and
               String.starts_with?(
                 evidence_ref.packet_ref,
                 "jido://v2/derived_state_attachment/run/"
               )
           end)

    assert Enum.any?(attachment.evidence_refs, fn evidence_ref ->
             evidence_ref.kind == :connection and
               evidence_ref.id == connection_id and
               evidence_ref.metadata.connector_id == "github"
           end)

    assert attachment.governance_refs == []
    assert DerivedStateAttachment.dump(attachment)
  end
end
