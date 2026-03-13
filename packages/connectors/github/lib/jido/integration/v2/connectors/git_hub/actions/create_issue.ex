defmodule Jido.Integration.V2.Connectors.GitHub.Actions.CreateIssue do
  @moduledoc false

  use Jido.Action,
    name: "github_create_issue",
    description: "Creates a synthetic GitHub issue for the first direct-runtime slice",
    schema: [
      repo: [type: :string, required: true],
      title: [type: :string, required: true],
      body: [type: :string, required: false]
    ]

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.RuntimeResult

  @impl true
  def run(params, context) do
    subject = context.credential_lease.subject

    auth_binding =
      ArtifactBuilder.digest(lease_value(context.credential_lease.payload, :access_token))

    issue_number = :erlang.phash2({params.repo, params.title, subject}, 10_000)

    artifact =
      ArtifactBuilder.build!(
        run_id: context.run_id,
        attempt_id: context.attempt_id,
        artifact_type: :tool_output,
        key: "github/#{context.run_id}/#{context.attempt_id}/issue_create.term",
        content: %{
          request: %{repo: params.repo, title: params.title, body: Map.get(params, :body)},
          response: %{issue_number: issue_number},
          auth_binding: auth_binding,
          execution_policy: context.policy_inputs.execution
        },
        metadata: %{
          connector: "github",
          capability_id: context.capability.id,
          auth_binding: auth_binding
        }
      )

    {:ok,
     RuntimeResult.new!(%{
       output: %{
         issue_number: issue_number,
         repo: params.repo,
         title: params.title,
         body: Map.get(params, :body),
         opened_by: subject,
         auth_binding: auth_binding
       },
       events: [
         %{
           type: "connector.github.issue.created",
           stream: :control,
           payload: %{
             repo: params.repo,
             issue_number: issue_number,
             auth_binding: auth_binding
           }
         }
       ],
       artifacts: [artifact]
     })}
  end

  defp lease_value(payload, key) do
    case Contracts.get(payload, key) do
      nil -> raise ArgumentError, "missing credential lease field #{inspect(key)}"
      value -> value
    end
  end
end
