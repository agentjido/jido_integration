defmodule Jido.Integration.V2.Apps.DevopsIncidentResponse.GitHubIssueConnector do
  @moduledoc false

  @behaviour Jido.Integration.V2.Connector

  alias Jido.Integration.V2.Apps.DevopsIncidentResponse.GitHubIssueHandler
  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.Ingress.Definition
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.TriggerSpec

  @connector_id "github"
  @trigger_id "github.issue.ingest"
  @signal_type "github.issue.opened"
  @signal_source "/ingress/webhook/github/issues.opened"
  @sensor_name "github_issue_ingest"
  @delivery_id_headers ["x-github-delivery"]
  @callback_topology :dynamic_per_install
  @signature_header "x-hub-signature-256"
  @verification_secret_name "webhook_secret"
  @conformance_webhook_secret "__route_resolved_webhook_secret__"

  @spec connector_id() :: String.t()
  def connector_id, do: @connector_id

  @spec trigger_id() :: String.t()
  def trigger_id, do: @trigger_id

  @spec capability_id() :: String.t()
  def capability_id, do: @trigger_id

  @spec signal_type() :: String.t()
  def signal_type, do: @signal_type

  @spec signal_source() :: String.t()
  def signal_source, do: @signal_source

  @spec delivery_id_headers() :: [String.t()]
  def delivery_id_headers, do: @delivery_id_headers

  @spec validation_ref() :: {module(), atom()}
  def validation_ref, do: {__MODULE__, :validate_issue_opened}

  @spec ingress_definitions() :: [Definition.t()]
  def ingress_definitions do
    [ingress_definition()]
  end

  @spec route_attrs(map()) :: map()
  def route_attrs(attrs) when is_map(attrs) do
    definition = ingress_definition()

    %{
      connector_id: connector_id(),
      tenant_id: Map.fetch!(attrs, :tenant_id),
      connection_id: Map.fetch!(attrs, :connection_id),
      install_id: Map.fetch!(attrs, :install_id),
      trigger_id: definition.trigger_id,
      capability_id: definition.capability_id,
      signal_type: definition.signal_type,
      signal_source: definition.signal_source,
      callback_topology: @callback_topology,
      delivery_id_headers: delivery_id_headers(),
      dedupe_ttl_seconds: definition.dedupe_ttl_seconds,
      verification: %{
        algorithm: :sha256,
        signature_header: @signature_header,
        secret_ref: %{
          credential_ref: Map.fetch!(attrs, :credential_ref),
          secret_key: @verification_secret_name
        }
      },
      validator: validation_ref()
    }
  end

  @impl true
  def manifest do
    Manifest.new!(%{
      connector: connector_id(),
      auth:
        AuthSpec.new!(%{
          binding_kind: :connection_id,
          auth_type: :oauth2,
          install: %{required: true},
          reauth: %{supported: true},
          requested_scopes: [],
          lease_fields: ["access_token"],
          secret_names: ["webhook_secret"]
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: "GitHub Incident Trigger",
          description: "Hosted webhook trigger for GitHub issue events",
          category: "developer_tools",
          tags: ["github", "webhook"],
          docs_refs: [],
          maturity: :experimental,
          publication: :internal
        }),
      operations: [],
      triggers: [
        TriggerSpec.new!(%{
          trigger_id: trigger_id(),
          name: "issue_ingest",
          display_name: "Issue ingest",
          description: "Receives hosted GitHub issue webhooks",
          runtime_class: :direct,
          delivery_mode: :webhook,
          handler: GitHubIssueHandler,
          config_schema: Zoi.map(description: "Webhook config"),
          signal_schema: Zoi.map(description: "Webhook signal"),
          permissions: %{required_scopes: []},
          checkpoint: %{},
          dedupe: %{},
          verification: %{secret_name: "webhook_secret"},
          policy: %{
            environment: %{allowed: [:prod]},
            sandbox: %{
              level: :standard,
              egress: :blocked,
              approvals: :auto,
              allowed_tools: ["devops_incident_response.github_issue_ingest"]
            }
          },
          consumer_surface: %{
            mode: :connector_local,
            reason: "Hosted webhook composition stays app-local"
          },
          schema_policy: %{
            config: :passthrough,
            signal: :passthrough,
            justification:
              "App-level hosted webhook handling preserves payload passthrough because it is not a normalized projected common sensor surface"
          },
          jido: %{
            sensor: %{
              name: @sensor_name,
              signal_type: signal_type(),
              signal_source: signal_source()
            }
          }
        })
      ],
      runtime_families: [:direct]
    })
  end

  def validate_issue_opened(%{action: "opened"}), do: :ok
  def validate_issue_opened(%{"action" => "opened"}), do: :ok
  def validate_issue_opened(_payload), do: {:error, :missing_action}

  defp ingress_definition do
    trigger = manifest().triggers |> List.first()

    Definition.from_trigger!(connector_id(), trigger, %{
      verification: %{
        algorithm: :sha256,
        secret: @conformance_webhook_secret,
        signature_header: @signature_header
      },
      validator: &validate_issue_opened/1
    })
  end
end

defmodule Jido.Integration.V2.Apps.DevopsIncidentResponse.GitHubIssueConnector.Conformance do
  @moduledoc false

  alias Jido.Integration.V2.Apps.DevopsIncidentResponse.GitHubIssueConnector

  @run_id "run-devops-incident-response-conformance"
  @attempt_id "#{@run_id}:1"
  @subject "octocat"
  @webhook_secret "incident-secret"

  @spec ingress_definitions() :: list()
  def ingress_definitions do
    GitHubIssueConnector.ingress_definitions()
  end

  @spec fixtures() :: [map()]
  def fixtures do
    [
      %{
        capability_id: GitHubIssueConnector.capability_id(),
        input: %{
          trigger: %{
            connector_id: GitHubIssueConnector.connector_id(),
            trigger_id: GitHubIssueConnector.trigger_id(),
            capability_id: GitHubIssueConnector.capability_id(),
            tenant_id: "tenant-devops",
            payload: %{
              "action" => "opened",
              "issue" => %{"number" => 101, "title" => "Database latency spike"},
              "repository" => %{"full_name" => "acme/api"}
            }
          }
        },
        credential_ref: credential_ref(),
        credential_lease: credential_lease(),
        context: %{
          run_id: @run_id,
          attempt_id: @attempt_id,
          attempt: 1
        },
        expect: %{
          output: %{
            "incident_key" => "acme/api#101",
            "summary" => "Database latency spike",
            "action" => "page_oncall",
            "attempt" => 1,
            "run_id" => @run_id
          },
          event_types: [
            "attempt.started",
            "connector.devops_incident_response.github_issue_ingested",
            "attempt.completed"
          ],
          artifact_types: [:log],
          artifact_keys: [
            "devops_incident_response/#{@run_id}/#{@attempt_id}/github_issue_ingest.term"
          ]
        }
      }
    ]
  end

  defp credential_ref do
    %{
      id: "cred-devops-incident-response-conformance",
      subject: @subject,
      scopes: ["repo"]
    }
  end

  defp credential_lease do
    %{
      lease_id: "lease-devops-incident-response-conformance",
      credential_ref_id: "cred-devops-incident-response-conformance",
      subject: @subject,
      scopes: ["repo"],
      payload: %{
        access_token: "gho-demo-conformance",
        webhook_secret: @webhook_secret
      },
      issued_at: ~U[2026-03-12 00:00:00Z],
      expires_at: ~U[2026-03-12 00:05:00Z]
    }
  end
end
