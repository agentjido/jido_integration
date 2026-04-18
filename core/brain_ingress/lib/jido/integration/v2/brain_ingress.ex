defmodule Jido.Integration.V2.BrainIngress do
  @moduledoc """
  Durable brain-to-lower-gateway invocation intake.
  """

  alias Jido.Integration.V2.BrainIngress.{StaticScopeResolver, SubmissionDedupe, SubmissionLedger}
  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.ExecutionGovernanceProjection.Verifier
  alias Jido.Integration.V2.Gateway
  alias Jido.Integration.V2.SubmissionRejection

  @type runtime_inputs :: %{
          required(:workspace_root) => String.t() | nil,
          required(:file_scope) => String.t() | nil,
          required(:routing_hints) => map(),
          required(:execution_family) => String.t(),
          required(:target_kind) => String.t(),
          required(:allowed_tools) => [String.t()]
        }

  @spec accept_invocation(BrainInvocation.t() | map(), keyword()) ::
          {:ok, Jido.Integration.V2.SubmissionAcceptance.t(), Gateway.t(), runtime_inputs()}
          | {:error, SubmissionRejection.t()}
  def accept_invocation(invocation, opts) do
    invocation = BrainInvocation.new!(invocation)
    ledger = submission_ledger!(opts)
    ledger_opts = Keyword.get(opts, :submission_ledger_opts, [])
    scope_resolver = Keyword.get(opts, :scope_resolver, StaticScopeResolver)
    scope_resolver_opts = Keyword.get(opts, :scope_resolver_opts, [])

    with :ok <-
           verify_projection(
             invocation,
             invocation.execution_governance_payload,
             invocation.gateway_request,
             invocation.runtime_request,
             invocation.boundary_request
           ),
         {:ok, resolved_scope} <-
           resolve_scope(
             invocation,
             scope_resolver,
             invocation.execution_governance_payload.workspace["logical_workspace_ref"],
             invocation.execution_governance_payload.sandbox["file_scope_ref"],
             scope_resolver_opts
           ),
         gateway <- build_gateway(invocation, resolved_scope),
         runtime_inputs <- build_runtime_inputs(invocation, resolved_scope),
         {:ok, acceptance} <- ledger.accept_submission(invocation, ledger_opts) do
      {:ok, acceptance, gateway, runtime_inputs}
    else
      {:error, %SubmissionRejection{} = rejection} ->
        _ = record_rejection(ledger, invocation, rejection, ledger_opts)
        {:error, rejection}

      {:error, reason} ->
        rejection = invalid_submission(invocation, reason)
        _ = record_rejection(ledger, invocation, rejection, ledger_opts)
        {:error, rejection}
    end
  end

  @doc """
  Fetch a durable submission acceptance by submission key.

  The backing submission ledger resolves through the configured
  `:jido_integration_v2_brain_ingress` application environment unless the
  caller overrides it via `:submission_ledger`.
  """
  @spec fetch_acceptance(String.t(), keyword()) ::
          {:ok, Jido.Integration.V2.SubmissionAcceptance.t()}
          | {:error, :tenant_mismatch}
          | :error
  def fetch_acceptance(submission_key, opts \\ []) when is_binary(submission_key) do
    ledger_opts = Keyword.get(opts, :submission_ledger_opts, [])
    ledger = submission_ledger!(opts)
    ledger.fetch_acceptance(submission_key, ledger_opts)
  end

  @doc """
  Lookup a durable submission by tenant-scoped `submission_dedupe_key`.
  """
  @spec lookup_submission(String.t(), String.t(), keyword()) ::
          {:accepted, Jido.Integration.V2.SubmissionAcceptance.t()}
          | {:rejected, SubmissionRejection.t()}
          | :never_seen
          | {:expired, DateTime.t()}
  def lookup_submission(submission_dedupe_key, tenant_id, opts \\ [])
      when is_binary(submission_dedupe_key) and is_binary(tenant_id) do
    ledger_opts = Keyword.get(opts, :submission_ledger_opts, [])
    ledger = submission_ledger!(opts)
    ledger.lookup_submission(submission_dedupe_key, tenant_id, ledger_opts)
  end

  defp verify_projection(
         invocation,
         projection,
         gateway_request,
         runtime_request,
         boundary_request
       ) do
    case Verifier.verify(projection, gateway_request, runtime_request, boundary_request) do
      :ok ->
        :ok

      {:error, :projection_mismatch, details} ->
        {:error,
         SubmissionRejection.new!(%{
           submission_key: invocation.submission_key,
           rejection_family: :projection_mismatch,
           reason_code: "shadow_projection_mismatch",
           retry_class: :never,
           redecision_required: false,
           details: details
         })}
    end
  end

  defp resolve_scope(
         invocation,
         scope_resolver,
         logical_workspace_ref,
         file_scope_ref,
         scope_resolver_opts
       ) do
    case scope_resolver.resolve(logical_workspace_ref, file_scope_ref, scope_resolver_opts) do
      {:ok, resolved_scope} ->
        {:ok, resolved_scope}

      {:error, {:scope_unresolvable, value}} ->
        {:error,
         SubmissionRejection.new!(%{
           submission_key: invocation.submission_key,
           rejection_family: :scope_unresolvable,
           reason_code: "workspace_ref_unresolved",
           retry_class: :after_redecision,
           redecision_required: true,
           details: %{"unresolved_ref" => value}
         })}
    end
  end

  defp build_gateway(invocation, resolved_scope) do
    sandbox = invocation.gateway_request["sandbox"]

    Gateway.new!(%{
      actor_id: invocation.actor_id,
      tenant_id: invocation.tenant_id,
      environment: nil,
      trace_id: invocation.trace_id,
      credential_ref: nil,
      runtime_class: invocation.runtime_class,
      allowed_operations: invocation.allowed_operations,
      sandbox: %{
        level: sandbox["level"],
        egress: sandbox["egress"],
        approvals: sandbox["approvals"],
        file_scope: resolved_scope.file_scope,
        allowed_tools: sandbox["allowed_tools"]
      },
      metadata: %{
        submission_key: invocation.submission_key,
        boundary_class: invocation.boundary_request["boundary_class"]
      }
    })
  end

  defp build_runtime_inputs(invocation, resolved_scope) do
    %{
      workspace_root: resolved_scope.workspace_root,
      file_scope: resolved_scope.file_scope,
      routing_hints: invocation.runtime_request["routing_hints"],
      execution_family: invocation.runtime_request["execution_family"],
      target_kind: invocation.runtime_request["target_kind"],
      allowed_tools: invocation.runtime_request["allowed_tools"]
    }
  end

  defp invalid_submission(invocation, reason) do
    SubmissionRejection.new!(%{
      submission_key: invocation.submission_key,
      rejection_family: :invalid_submission,
      reason_code: normalize_reason_code(reason),
      retry_class: :never,
      redecision_required: false,
      details: %{"reason" => inspect(reason)}
    })
  end

  defp normalize_reason_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_reason_code(_reason), do: "invalid_submission"

  defp record_rejection(ledger, invocation, rejection, ledger_opts) do
    if Code.ensure_loaded?(ledger) and function_exported?(ledger, :record_rejection, 3) do
      ledger.record_rejection(invocation, rejection, ledger_opts)
    else
      :ok
    end
  end

  defp submission_ledger!(opts) do
    case Keyword.get(opts, :submission_ledger, configured_submission_ledger()) do
      nil ->
        raise ArgumentError,
              "brain_ingress requires :submission_ledger implementing #{inspect(SubmissionLedger)}"

      ledger ->
        ledger
    end
  end

  @spec submission_dedupe_key!(BrainInvocation.t()) :: String.t()
  def submission_dedupe_key!(%BrainInvocation{} = invocation),
    do: SubmissionDedupe.key!(invocation)

  defp configured_submission_ledger do
    Application.get_env(:jido_integration_v2_brain_ingress, :submission_ledger)
  end
end
