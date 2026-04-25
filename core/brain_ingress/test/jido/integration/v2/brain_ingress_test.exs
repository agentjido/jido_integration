defmodule Jido.Integration.V2.BrainIngressTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.AuthorityAuditEnvelope
  alias Jido.Integration.V2.BrainIngress
  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.ExecutionGovernanceProjection
  alias Jido.Integration.V2.ExecutionGovernanceProjection.Compiler
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.SubmissionIdentity
  alias Jido.Integration.V2.SubmissionRejection

  defmodule Ledger do
    @behaviour Jido.Integration.V2.BrainIngress.SubmissionLedger

    def accept_submission(invocation, opts) do
      agent = Keyword.fetch!(opts, :agent)
      dedupe_key = invocation.extensions["submission_dedupe_key"]

      Agent.get_and_update(agent, fn state ->
        case Map.get(state, {invocation.tenant_id, dedupe_key}) do
          nil ->
            acceptance =
              SubmissionAcceptance.new!(%{
                submission_key: invocation.submission_key,
                submission_receipt_ref: "receipt://submission/#{map_size(state) + 1}",
                status: :accepted,
                ledger_version: 1
              })

            {{:ok, acceptance}, Map.put(state, {invocation.tenant_id, dedupe_key}, acceptance)}

          acceptance ->
            duplicate =
              SubmissionAcceptance.new!(%{
                SubmissionAcceptance.dump(acceptance)
                | status: :duplicate
              })

            {{:ok, duplicate}, state}
        end
      end)
    end

    def lookup_submission(submission_dedupe_key, tenant_id, opts) do
      agent = Keyword.fetch!(opts, :agent)

      Agent.get(agent, fn state ->
        case Map.fetch(state, {tenant_id, submission_dedupe_key}) do
          {:ok, acceptance} -> {:accepted, acceptance}
          :error -> :never_seen
        end
      end)
    end

    def fetch_acceptance(submission_key, opts) do
      agent = Keyword.fetch!(opts, :agent)

      Agent.get(agent, fn state ->
        case find_acceptance(state, submission_key) do
          {:ok, acceptance} -> {:ok, acceptance}
          :error -> :error
          nil -> :error
        end
      end)
    end

    def record_rejection(invocation, rejection, opts) do
      agent = Keyword.fetch!(opts, :agent)
      dedupe_key = invocation.extensions["submission_dedupe_key"]
      Agent.update(agent, &Map.put(&1, {:rejection, invocation.tenant_id, dedupe_key}, rejection))
      :ok
    end

    def expire_submissions(_opts), do: 0

    defp find_acceptance(state, submission_key) do
      Enum.find_value(state, fn
        {{_tenant_id, _dedupe_key},
         %SubmissionAcceptance{submission_key: ^submission_key} = acceptance} ->
          {:ok, acceptance}

        _other ->
          nil
      end)
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

  test "uses the configured submission ledger when callers omit the override", %{agent: agent} do
    previous_ledger = Application.get_env(:jido_integration_v2_brain_ingress, :submission_ledger)
    invocation = brain_invocation_fixture()

    Application.put_env(:jido_integration_v2_brain_ingress, :submission_ledger, Ledger)

    on_exit(fn ->
      case previous_ledger do
        nil ->
          Application.delete_env(:jido_integration_v2_brain_ingress, :submission_ledger)

        ledger ->
          Application.put_env(:jido_integration_v2_brain_ingress, :submission_ledger, ledger)
      end
    end)

    assert {:ok, %SubmissionAcceptance{} = acceptance, _gateway, _runtime_inputs} =
             BrainIngress.accept_invocation(
               invocation,
               submission_ledger_opts: [agent: agent],
               scope_resolver: Resolver,
               scope_resolver_opts: [
                 mapping: %{
                   "workspace://tenant-1/root" => "/srv/workspaces/tenant-1"
                 }
               ]
             )

    assert {:ok, ^acceptance} =
             BrainIngress.fetch_acceptance(
               invocation.submission_key,
               submission_ledger_opts: [agent: agent]
             )
  end

  test "accepts a submission once the shadows verify and scopes resolve", %{agent: agent} do
    invocation = brain_invocation_fixture()

    assert {:ok, %SubmissionAcceptance{status: :accepted} = acceptance, gateway, runtime_inputs} =
             BrainIngress.accept_invocation(
               invocation,
               submission_ledger: Ledger,
               submission_ledger_opts: [agent: agent],
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
  end

  test "returns a typed scope rejection when the workspace ref cannot resolve", %{agent: agent} do
    invocation = brain_invocation_fixture()

    assert {:error, %SubmissionRejection{} = rejection} =
             BrainIngress.accept_invocation(
               invocation,
               submission_ledger: Ledger,
               submission_ledger_opts: [agent: agent],
               scope_resolver: Resolver,
               scope_resolver_opts: [mapping: %{}]
             )

    assert rejection.rejection_family == :scope_unresolvable
    assert rejection.retry_class == :after_redecision
  end

  test "records a typed scope rejection even when the ledger module is not yet loaded", %{
    agent: agent
  } do
    invocation = brain_invocation_fixture()
    ledger = compile_lazy_ledger!()

    try do
      :code.purge(ledger)
      :code.delete(ledger)

      assert {:error, %SubmissionRejection{} = rejection} =
               BrainIngress.accept_invocation(
                 invocation,
                 submission_ledger: ledger,
                 submission_ledger_opts: [agent: agent],
                 scope_resolver: Resolver,
                 scope_resolver_opts: [mapping: %{}]
               )

      assert rejection.rejection_family == :scope_unresolvable

      assert Agent.get(agent, &Map.fetch(&1, {:rejection, invocation.tenant_id, "dedupe-1"})) ==
               {:ok, rejection}
    after
      :code.purge(ledger)
      :code.delete(ledger)
    end
  end

  test "returns a typed projection mismatch rejection before scope or ledger work", %{
    agent: agent
  } do
    invocation =
      brain_invocation_fixture(fn shadows ->
        put_in(shadows.gateway_request["sandbox"]["level"], :none)
      end)

    assert {:error, %SubmissionRejection{} = rejection} =
             BrainIngress.accept_invocation(
               invocation,
               submission_ledger: Ledger,
               submission_ledger_opts: [agent: agent],
               scope_resolver: Resolver,
               scope_resolver_opts: [
                 mapping: %{
                   "workspace://tenant-1/root" => "/srv/workspaces/tenant-1"
                 }
               ]
             )

    assert rejection.rejection_family == :projection_mismatch
    assert rejection.retry_class == :never
  end

  defp brain_invocation_fixture(shadow_mutator \\ & &1) do
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
          "acceptable_attestation" => ["local-erlexec-weak"],
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
        },
        extensions: %{}
      })

    shadows =
      governance_payload
      |> Compiler.compile!()
      |> shadow_mutator.()

    BrainInvocation.new!(%{
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
      gateway_request: shadows.gateway_request,
      runtime_request: shadows.runtime_request,
      boundary_request: shadows.boundary_request,
      execution_intent_family: "process",
      execution_intent: %{"argv" => ["echo", "hello"]},
      extensions: %{"submission_dedupe_key" => "dedupe-1"}
    })
  end

  defp compile_lazy_ledger! do
    module =
      Module.concat(
        __MODULE__,
        :"LazyLedger#{unique_lazy_ledger_token()}"
      )

    root = Path.join(System.tmp_dir!(), "jido_integration_v2_brain_ingress_lazy_ledger")
    File.mkdir_p!(root)
    beam_dir = Path.join(root, Atom.to_string(module))
    File.mkdir_p!(beam_dir)
    source_path = Path.join(beam_dir, "lazy_ledger.ex")

    File.write!(
      source_path,
      """
      defmodule #{inspect(module)} do
        @behaviour Jido.Integration.V2.BrainIngress.SubmissionLedger

        def accept_submission(_invocation, _opts) do
          raise "lazy ledger accept_submission/2 should not be called in rejection tests"
        end

        def fetch_acceptance(_submission_key, _opts), do: :error

        def lookup_submission(_submission_dedupe_key, _tenant_id, _opts), do: :never_seen

        def record_rejection(invocation, rejection, opts) do
          agent = Keyword.fetch!(opts, :agent)
          dedupe_key = invocation.extensions["submission_dedupe_key"]
          Agent.update(agent, &Map.put(&1, {:rejection, invocation.tenant_id, dedupe_key}, rejection))
          :ok
        end

        def expire_submissions(_opts), do: 0
      end
      """
    )

    Code.prepend_path(beam_dir)

    {:ok, [^module], %{compile_warnings: [], runtime_warnings: []}} =
      Kernel.ParallelCompiler.compile_to_path([source_path], beam_dir, return_diagnostics: true)

    module
  end

  defp unique_lazy_ledger_token do
    :erlang.phash2(
      {:os.getpid(), System.unique_integer([:positive]), System.monotonic_time(), make_ref()},
      1_000_000_000
    )
  end
end
