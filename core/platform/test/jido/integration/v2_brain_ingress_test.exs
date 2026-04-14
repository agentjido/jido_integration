defmodule Jido.Integration.V2BrainIngressFacadeTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2
  alias Jido.Integration.V2.AuthorityAuditEnvelope
  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.ExecutionGovernanceProjection
  alias Jido.Integration.V2.ExecutionGovernanceProjection.Compiler
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.SubmissionIdentity
  alias Jido.Integration.V2.SubmissionRejection

  defmodule Ledger do
    @behaviour Jido.Integration.V2.BrainIngress.SubmissionLedger

    def accept_submission(_invocation, opts) do
      agent = Keyword.fetch!(opts, :agent)
      invocation = Keyword.fetch!(opts, :invocation)

      Agent.get_and_update(agent, fn state ->
        acceptance =
          SubmissionAcceptance.new!(%{
            submission_key: invocation.submission_key,
            submission_receipt_ref: "receipt://submission/#{map_size(state) + 1}",
            status: :accepted,
            ledger_version: 1
          })

        {{:ok, acceptance}, Map.put(state, invocation.submission_key, acceptance)}
      end)
    end

    def fetch_acceptance(submission_key, opts) do
      agent = Keyword.fetch!(opts, :agent)

      Agent.get(agent, fn state ->
        case Map.fetch(state, submission_key) do
          {:ok, acceptance} -> {:ok, acceptance}
          :error -> :error
        end
      end)
    end

    def record_rejection(submission_key, rejection, opts) do
      agent = Keyword.fetch!(opts, :agent)
      Agent.update(agent, &Map.put(&1, {:rejection, submission_key}, rejection))
      :ok
    end
  end

  defmodule Resolver do
    @behaviour Jido.Integration.V2.BrainIngress.ScopeResolver

    def resolve(logical_workspace_ref, file_scope_ref, opts) do
      mapping = Keyword.get(opts, :mapping, %{})

      with {:ok, workspace_root} <- fetch(mapping, logical_workspace_ref),
           {:ok, file_scope} <- fetch(mapping, file_scope_ref) do
        {:ok, %{workspace_root: workspace_root, file_scope: file_scope}}
      end
    end

    defp fetch(_mapping, nil), do: {:ok, nil}

    defp fetch(mapping, value) do
      case Map.fetch(mapping, value) do
        {:ok, resolved} -> {:ok, resolved}
        :error -> {:error, {:scope_unresolvable, value}}
      end
    end
  end

  setup do
    {:ok, agent} = Agent.start_link(fn -> %{} end)
    %{agent: agent}
  end

  test "accept_brain_invocation/2 exposes the durable brain-ingress seam", %{agent: agent} do
    invocation = brain_invocation_fixture()

    assert {:ok, %SubmissionAcceptance{status: :accepted} = acceptance, gateway, runtime_inputs} =
             V2.accept_brain_invocation(
               invocation,
               submission_ledger: Ledger,
               submission_ledger_opts: [agent: agent, invocation: invocation],
               scope_resolver: Resolver,
               scope_resolver_opts: [
                 mapping: %{
                   "workspace://tenant-1/root" => "/srv/workspaces/tenant-1"
                 }
               ]
             )

    assert acceptance.submission_key == invocation.submission_key
    assert gateway.sandbox.file_scope == "/srv/workspaces/tenant-1"
    assert runtime_inputs.workspace_root == "/srv/workspaces/tenant-1"
    assert runtime_inputs.execution_family == "process"
  end

  test "accept_brain_invocation/2 returns typed submission rejection errors", %{agent: agent} do
    invocation = brain_invocation_fixture()

    assert {:error, %SubmissionRejection{} = rejection} =
             V2.accept_brain_invocation(
               invocation,
               submission_ledger: Ledger,
               submission_ledger_opts: [agent: agent, invocation: invocation],
               scope_resolver: Resolver,
               scope_resolver_opts: [mapping: %{}]
             )

    assert rejection.rejection_family == :scope_unresolvable
    assert rejection.retry_class == :after_redecision
  end

  defp brain_invocation_fixture do
    identity =
      SubmissionIdentity.new!(%{
        submission_family: :invocation,
        tenant_id: "tenant-1",
        session_id: "session-1",
        request_id: "request-1",
        invocation_request_id: "invoke-1",
        causal_group_id: "cg-1",
        target_id: "target-1",
        target_kind: "cli",
        selected_step_id: "step-1",
        authority_decision_id: "decision-1",
        execution_governance_id: "governance-1",
        execution_intent_family: "process"
      })

    authority_payload =
      AuthorityAuditEnvelope.new!(%{
        contract_version: "v1",
        decision_id: "decision-1",
        tenant_id: "tenant-1",
        request_id: "request-1",
        policy_version: "policy-7",
        boundary_class: "hazmat",
        trust_profile: "trusted_operator",
        approval_profile: "manual",
        egress_profile: "restricted",
        workspace_profile: "workspace_attached",
        resource_profile: "balanced",
        decision_hash: String.duplicate("f", 64),
        extensions: %{}
      })

    governance_payload =
      ExecutionGovernanceProjection.new!(%{
        contract_version: "v1",
        execution_governance_id: "governance-1",
        authority_ref: %{
          "decision_id" => "decision-1",
          "policy_version" => "policy-7",
          "decision_hash" => String.duplicate("f", 64)
        },
        sandbox: %{
          "level" => "strict",
          "egress" => "restricted",
          "approvals" => "manual",
          "allowed_tools" => ["bash", "git"],
          "file_scope_ref" => "workspace://tenant-1/root",
          "file_scope_hint" => "/srv/workspaces/tenant-1"
        },
        boundary: %{
          "boundary_class" => "hazmat",
          "trust_profile" => "trusted_operator",
          "requested_attach_mode" => "attach_if_exists",
          "requested_ttl_ms" => 60_000
        },
        topology: %{
          "topology_intent_id" => "topology-1",
          "session_mode" => "attached",
          "coordination_mode" => "single_target",
          "topology_epoch" => 9,
          "routing_hints" => %{
            "runtime_driver" => "asm",
            "runtime_provider" => "codex"
          }
        },
        workspace: %{
          "workspace_profile" => "workspace_attached",
          "logical_workspace_ref" => "workspace://tenant-1/root",
          "mutability" => "read_write"
        },
        resources: %{
          "resource_profile" => "balanced",
          "cpu_class" => "medium",
          "memory_class" => "medium",
          "wall_clock_budget_ms" => 300_000
        },
        placement: %{
          "execution_family" => "process",
          "placement_intent" => "host_local",
          "target_kind" => "cli",
          "node_affinity" => "same_node"
        },
        operations: %{
          "allowed_operations" => ["shell.exec"],
          "effect_classes" => ["filesystem", "process"]
        }
      })

    compiled_projection = Compiler.compile!(governance_payload)

    BrainInvocation.new!(%{
      contract_version: "v1",
      submission_identity: identity,
      request_id: "request-1",
      session_id: "session-1",
      tenant_id: "tenant-1",
      trace_id: "trace-1",
      actor_id: "actor-1",
      target_id: "target-1",
      target_kind: "cli",
      runtime_class: :direct,
      allowed_operations: ["shell.exec"],
      authority_payload: authority_payload,
      execution_governance_payload: governance_payload,
      gateway_request: compiled_projection.gateway_request,
      runtime_request: compiled_projection.runtime_request,
      boundary_request: compiled_projection.boundary_request,
      execution_intent_family: "process",
      execution_intent: %{"argv" => ["echo", "hello"]},
      extensions: %{}
    })
  end
end
