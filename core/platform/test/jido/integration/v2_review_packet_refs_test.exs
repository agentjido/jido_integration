defmodule Jido.Integration.V2ReviewPacketRefsTest do
  use Jido.Integration.V2.ConnectorContractCase, async: false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.GitHub.ClientFactory
  alias Jido.Integration.V2.Connectors.GitHub.Fixtures, as: GitHubFixtures
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.ReviewProjection

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
    assert ReviewProjection.dump(ReviewProjection.new!(packet.metadata)) == packet.metadata
    assert Jason.encode!(packet.metadata)
  end

  test "review_packet redacts install callback and PKCE auth-control material" do
    register_connector!(@github.connector)

    pkce_verifier = "github-review-pkce"

    assert {:ok, %{install: started_install}} =
             V2.start_install(@github.connector_id, @github.tenant_id, %{
               actor_id: "review-redaction-operator",
               auth_type: :oauth2,
               profile_id: "oauth_user",
               flow_kind: :manual_callback,
               state_token: "state-review-redaction",
               pkce_verifier_digest: ArtifactBuilder.digest(pkce_verifier),
               subject: "review-redaction-operator",
               requested_scopes: ["repo"],
               metadata: %{
                 redirect_uri: "/auth/github/callback",
                 client_secret: "review-client-secret"
               }
             })

    assert {:ok, %{install: completed_install, connection: connection}} =
             started_install.install_id
             |> then(fn install_id ->
               with {:ok, _callback} <-
                      V2.resolve_install_callback(%{
                        "callback_token" => started_install.callback_token,
                        "state_token" => started_install.state_token,
                        "pkce_verifier" => pkce_verifier,
                        "callback_uri" => "/auth/github/callback?code=oauth-review-code"
                      }) do
                 V2.complete_install(install_id, %{
                   subject: "review-redaction-operator",
                   granted_scopes: ["repo"],
                   secret: %{access_token: "gho_review_redaction"},
                   secret_source: :hosted_callback,
                   source: :hosted_callback
                 })
               end
             end)

    assert {:ok, result} =
             V2.invoke(
               "github.issue.create",
               %{
                 repo: "agentjido/jido_integration_v2",
                 title: "Review packet redaction",
                 body: "Verify auth-control redaction"
               },
               invoke_opts("github.issue.create", connection.connection_id, @github_create_spec)
             )

    assert {:ok, packet} =
             V2.review_packet(result.run.run_id, %{attempt_id: result.attempt.attempt_id})

    assert packet.install.install_id == completed_install.install_id
    assert packet.install.connection_id == connection.connection_id
    assert packet.install.callback_token == Redaction.redacted()
    assert packet.install.state_token == Redaction.redacted()
    assert packet.install.pkce_verifier_digest == Redaction.redacted()
    assert packet.install.callback_uri == Redaction.redacted()
    refute Map.has_key?(packet.install.metadata, :redirect_uri)
    assert packet.install.metadata.client_secret == Redaction.redacted()
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
