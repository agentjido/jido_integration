defmodule Jido.Integration.V2.ControlPlane.GovernedLowerAdmission do
  @moduledoc """
  Admission checks for the governed lower envelope before provider/runtime effects.
  """

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane.TreAdapter
  alias Jido.Integration.V2.GovernedLowerDenial
  alias Jido.Integration.V2.GovernedLowerEnvelope

  @sandbox_rank %{strict: 0, standard: 1, none: 2}
  @manifest_denial_classes %{
    stale: :manifest_stale,
    invalid: :manifest_invalid,
    refresh_required: :manifest_stale,
    quarantined: :manifest_quarantined
  }

  @spec admit(Capability.t(), String.t(), keyword()) ::
          {:ok, GovernedLowerEnvelope.t() | nil}
          | {:error, GovernedLowerDenial.t() | Exception.t()}
  def admit(%Capability{} = capability, capability_id, opts) when is_list(opts) do
    case Keyword.fetch(opts, :governed_lower_envelope) do
      :error ->
        {:ok, nil}

      {:ok, attrs} ->
        with {:ok, envelope} <- GovernedLowerEnvelope.new(attrs),
             :ok <- validate_envelope(capability, capability_id, envelope, opts) do
          {:ok, envelope}
        else
          {:deny, denial_class, reason, %GovernedLowerEnvelope{} = envelope} ->
            {:error, denial(envelope, denial_class, reason)}

          {:error, %ArgumentError{} = error} ->
            {:error, error}
        end
    end
  end

  defp validate_envelope(%Capability{} = capability, capability_id, envelope, opts) do
    with :ok <- require_dispatchable(envelope, opts),
         :ok <- require_capability_match(envelope, capability_id),
         :ok <- require_connector_match(envelope, capability),
         :ok <- require_manifest_active(envelope),
         :ok <- require_lower_runtime_supported(envelope, capability),
         :ok <- require_tenant_match(envelope, opts),
         :ok <- require_trace_match(envelope, opts),
         :ok <- require_resource_scopes(envelope),
         :ok <- require_sandbox_not_downgraded(envelope, opts) do
      require_attestation_satisfied(envelope, opts)
    end
  end

  defp require_dispatchable(%GovernedLowerEnvelope{} = envelope, opts) do
    if GovernedLowerEnvelope.dispatchable?(envelope) or tre_adapter_enabled?(envelope, opts) do
      :ok
    else
      {:deny, :lower_runtime_unavailable,
       "lower runtime kind #{inspect(envelope.lower_runtime_kind)} is reserved or unavailable",
       envelope}
    end
  end

  defp tre_adapter_enabled?(%GovernedLowerEnvelope{lower_runtime_kind: :tre_rhai}, opts),
    do: TreAdapter.enabled?(opts)

  defp tre_adapter_enabled?(%GovernedLowerEnvelope{}, _opts), do: false

  defp require_capability_match(%GovernedLowerEnvelope{} = envelope, capability_id) do
    cond do
      envelope.capability_id != capability_id ->
        {:deny, :capability_denied,
         "envelope capability #{inspect(envelope.capability_id)} does not match requested capability #{inspect(capability_id)}",
         envelope}

      envelope.action_id != capability_id ->
        {:deny, :capability_denied,
         "envelope action #{inspect(envelope.action_id)} does not match requested capability #{inspect(capability_id)}",
         envelope}

      true ->
        :ok
    end
  end

  defp require_connector_match(%GovernedLowerEnvelope{connector_ref: nil}, %Capability{}), do: :ok

  defp require_connector_match(%GovernedLowerEnvelope{} = envelope, %Capability{} = capability) do
    valid_refs = [capability.connector, "jido/connectors/#{capability.connector}"]

    if envelope.connector_ref in valid_refs do
      :ok
    else
      {:deny, :manifest_invalid,
       "envelope connector_ref #{inspect(envelope.connector_ref)} does not match capability connector #{inspect(capability.connector)}",
       envelope}
    end
  end

  defp require_manifest_active(%GovernedLowerEnvelope{connector_manifest_state: nil}), do: :ok
  defp require_manifest_active(%GovernedLowerEnvelope{connector_manifest_state: :active}), do: :ok

  defp require_manifest_active(%GovernedLowerEnvelope{} = envelope) do
    denial_class =
      Map.get(@manifest_denial_classes, envelope.connector_manifest_state, :manifest_invalid)

    {:deny, denial_class,
     "connector manifest state #{inspect(envelope.connector_manifest_state)} cannot dispatch lower effects",
     envelope}
  end

  defp require_lower_runtime_supported(
         %GovernedLowerEnvelope{} = envelope,
         %Capability{} = capability
       ) do
    supported_kinds =
      capability.metadata
      |> Contracts.get(:lower_runtime_kinds, [])
      |> Enum.map(&Contracts.validate_lower_runtime_kind!/1)

    if envelope.lower_runtime_kind in supported_kinds do
      :ok
    else
      {:deny, :runtime_profile_incompatible,
       "capability #{inspect(capability.id)} does not support lower runtime kind #{inspect(envelope.lower_runtime_kind)}",
       envelope}
    end
  end

  defp require_tenant_match(%GovernedLowerEnvelope{} = envelope, opts) do
    case Keyword.get(opts, :tenant_id) do
      nil ->
        :ok

      tenant_id when tenant_id == envelope.tenant_ref ->
        :ok

      tenant_id ->
        {:deny, :authority_denied,
         "envelope tenant #{inspect(envelope.tenant_ref)} does not match invocation tenant #{inspect(tenant_id)}",
         envelope}
    end
  end

  defp require_trace_match(%GovernedLowerEnvelope{} = envelope, opts) do
    case Keyword.get(opts, :trace_id) do
      nil ->
        :ok

      trace_id when trace_id == envelope.trace_id ->
        :ok

      trace_id ->
        {:deny, :authority_denied,
         "envelope trace #{inspect(envelope.trace_id)} does not match invocation trace #{inspect(trace_id)}",
         envelope}
    end
  end

  defp require_resource_scopes(%GovernedLowerEnvelope{} = envelope) do
    unresolved? =
      Enum.any?(envelope.resource_scope_refs, fn
        "unresolved://" <> _rest -> true
        _scope -> false
      end)

    if unresolved? do
      {:deny, :resource_scope_unresolvable, "envelope contains unresolved resource scope refs",
       envelope}
    else
      :ok
    end
  end

  defp require_sandbox_not_downgraded(%GovernedLowerEnvelope{} = envelope, opts) do
    requested_level = posture_sandbox_level(envelope.sandbox_level)

    required_level =
      opts |> Keyword.get(:sandbox, %{}) |> sandbox_level() |> posture_sandbox_level()

    cond do
      is_nil(requested_level) or is_nil(required_level) ->
        :ok

      Map.fetch!(@sandbox_rank, requested_level) <= Map.fetch!(@sandbox_rank, required_level) ->
        :ok

      true ->
        {:deny, :sandbox_downgrade,
         "envelope sandbox #{inspect(envelope.sandbox_level)} is weaker than required sandbox #{inspect(required_level)}",
         envelope}
    end
  end

  defp require_attestation_satisfied(%GovernedLowerEnvelope{} = envelope, opts) do
    case attestation_refs(opts) do
      [] ->
        :ok

      refs ->
        if Enum.any?(refs, &(&1 in envelope.acceptable_attestation)) do
          :ok
        else
          {:deny, :attestation_unsatisfied,
           "runtime attestation refs do not satisfy the governed lower envelope", envelope}
        end
    end
  end

  defp sandbox_level(%{} = sandbox) do
    Contracts.get(sandbox, :level)
  end

  defp sandbox_level(_sandbox), do: nil

  defp posture_sandbox_level(level) when level in [:strict, :standard, :none], do: level

  defp posture_sandbox_level(level) when is_binary(level) do
    case level do
      "strict" -> :strict
      "standard" -> :standard
      "none" -> :none
      _other -> nil
    end
  end

  defp posture_sandbox_level(_level), do: nil

  defp attestation_refs(opts) do
    opts
    |> Keyword.get(:attestation_refs, Keyword.get(opts, :acceptable_attestation, []))
    |> List.wrap()
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
  end

  defp denial(%GovernedLowerEnvelope{} = envelope, denial_class, reason) do
    GovernedLowerDenial.new!(%{
      lower_denial_ref:
        "lower-denial://#{URI.encode_www_form(envelope.lower_request_ref)}/#{denial_class}",
      lower_request_ref: envelope.lower_request_ref,
      lower_runtime_kind: envelope.lower_runtime_kind,
      denial_class: denial_class,
      reason: reason,
      tenant_ref: envelope.tenant_ref,
      subject_ref: envelope.subject_ref,
      run_ref: envelope.run_ref,
      workflow_ref: envelope.workflow_ref,
      attempt_ref: envelope.attempt_ref,
      trace_id: envelope.trace_id,
      authority_ref: envelope.authority_ref,
      authority_decision_hash: envelope.authority_decision_hash,
      capability_id: envelope.capability_id,
      action_id: envelope.action_id,
      connector_manifest_ref: envelope.connector_manifest_ref,
      connector_manifest_hash: envelope.connector_manifest_hash,
      capability_negotiation_ref: envelope.capability_negotiation_ref,
      policy_bundle_ref: envelope.policy_bundle_ref,
      cedar_schema_ref: envelope.cedar_schema_ref,
      script_ref: envelope.script_ref,
      resource_scope_refs: envelope.resource_scope_refs,
      sandbox_profile_ref: envelope.sandbox_profile_ref,
      extensions: %{
        "jido_integration" => %{
          "stage" => "governed_lower_admission"
        }
      }
    })
  end
end
