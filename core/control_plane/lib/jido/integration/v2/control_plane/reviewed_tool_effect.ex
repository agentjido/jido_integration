defmodule Jido.Integration.V2.ControlPlane.ReviewedToolEffect do
  @moduledoc false

  alias Citadel.Governance.ToolEffectAuthority
  alias Citadel.ScopedGrant

  @spec permission_mode(map(), map(), keyword()) ::
          {:ok, :auto | nil}
          | {:error,
             :invalid_reviewed_tool_effect_evidence
             | :reviewed_tool_effect_authority_denied}
  def permission_mode(input, binding, opts \\ [])

  def permission_mode(%{} = input, %{} = binding, opts) when is_list(opts) do
    case evidence(input) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, evidence} ->
        authorize(evidence, binding, opts)

      :error ->
        {:error, :invalid_reviewed_tool_effect_evidence}
    end
  end

  def permission_mode(_input, _binding, _opts),
    do: {:error, :invalid_reviewed_tool_effect_evidence}

  defp authorize(evidence, binding, opts) do
    authority = Keyword.get(opts, :authority, ToolEffectAuthority)
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now() end)
    authority_ref = map_value(binding, :authority_ref)

    with {:ok, %ScopedGrant{} = grant} <- authority.fetch_grant(authority_ref),
         :ok <- authority.verify_grant(authority_ref, grant_binding(grant), now),
         true <- exact_runtime_binding?(grant, evidence, binding) do
      {:ok, :auto}
    else
      _denied -> {:error, :reviewed_tool_effect_authority_denied}
    end
  end

  defp evidence(input) do
    case map_value(input, :authority_metadata) do
      nil ->
        {:ok, nil}

      %{} = authority ->
        workspace = map_value(input, :workspace)

        if is_map(workspace) and evidence_present?(authority, workspace),
          do: {:ok, %{authority: authority, workspace: workspace}},
          else: :error

      _invalid ->
        :error
    end
  end

  defp evidence_present?(authority, workspace) do
    Enum.all?(
      [
        map_value(authority, :grant_ref),
        map_value(authority, :decision_ref),
        map_value(authority, :review_ref),
        map_value(authority, :effect_ref),
        map_value(workspace, :workspace_ref),
        map_value(workspace, :relative_path),
        map_value(workspace, :content_digest)
      ],
      &present_string?/1
    )
  end

  defp exact_runtime_binding?(grant, evidence, binding) do
    scope = grant.scope
    authority = evidence.authority
    workspace = evidence.workspace

    grant.grant_ref == map_value(binding, :authority_ref) and
      grant.grant_ref == map_value(authority, :grant_ref) and
      grant.decision_ref == map_value(binding, :authority_decision_ref) and
      grant.decision_ref == map_value(authority, :decision_ref) and
      grant.policy_artifact_ref == map_value(binding, :operation_policy_ref) and
      grant.tenant_ref == map_value(binding, :tenant_ref) and
      grant.effect_ref == map_value(binding, :effect_ref) and
      grant.effect_ref == map_value(authority, :effect_ref) and
      grant.operation_ref == map_value(binding, :operation_ref) and
      grant.capability_id == map_value(binding, :capability_id) and
      scope["provider_family"] == "codex" and
      scope["provider_account_ref"] == map_value(binding, :provider_account_ref) and
      scope["credential_lease_ref"] == map_value(binding, :credential_lease_ref) and
      scope["credential_generation"] == map_value(binding, :credential_generation) and
      scope["managed_session_ref"] == map_value(binding, :managed_session_ref) and
      scope["session_generation"] == map_value(binding, :session_generation) and
      scope["review_ref"] == map_value(authority, :review_ref) and
      scope["workspace_policy"] == "isolated_disposable_workspace" and
      scope["workspace_ref"] == map_value(binding, :workspace_ref) and
      scope["workspace_ref"] == map_value(workspace, :workspace_ref) and
      scope["workspace_root_digest"] == workspace_digest(map_value(binding, :workspace_root)) and
      scope["relative_path"] == map_value(workspace, :relative_path) and
      scope["operation_class"] == "create_or_replace" and
      scope["reviewed_content_digest"] == map_value(workspace, :content_digest) and
      scope["target_ref"] == map_value(binding, :target_ref) and
      scope["attempt_ref"] == map_value(binding, :attempt_ref)
  end

  defp grant_binding(%ScopedGrant{} = grant) do
    scope = grant.scope

    %{
      decision_ref: scope["authority_decision_ref"],
      input_digest: scope["input_digest"],
      policy_ref: scope["policy_ref"],
      policy_version: scope["policy_version"],
      tenant_ref: grant.tenant_ref,
      actor_ref: grant.actor_ref,
      subject_ref: grant.subject_ref,
      provider_family: scope["provider_family"],
      provider_account_ref: scope["provider_account_ref"],
      credential_lease_ref: scope["credential_lease_ref"],
      credential_generation: scope["credential_generation"],
      managed_session_ref: scope["managed_session_ref"],
      session_generation: scope["session_generation"],
      review_ref: scope["review_ref"],
      workspace_policy: scope["workspace_policy"],
      workspace_ref: scope["workspace_ref"],
      workspace_root_digest: scope["workspace_root_digest"],
      relative_path: scope["relative_path"],
      operation_ref: grant.operation_ref,
      operation_class: scope["operation_class"],
      capability_id: grant.capability_id,
      reviewed_content_digest: scope["reviewed_content_digest"],
      target_ref: scope["target_ref"],
      attempt_ref: scope["attempt_ref"],
      effect_ref: grant.effect_ref
    }
  end

  defp workspace_digest(value) when is_binary(value) do
    "sha256:" <> (:crypto.hash(:sha256, value) |> Base.encode16(case: :lower))
  end

  defp workspace_digest(_value), do: nil

  defp map_value(%{} = map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp map_value(_value, _key), do: nil

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""
end
