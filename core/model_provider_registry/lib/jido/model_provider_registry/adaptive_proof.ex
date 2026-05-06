defmodule Jido.ModelProviderRegistry.AdaptiveProof do
  @moduledoc """
  Ref-only adaptive proof materialization for provider and SDK adapter rows.
  """

  @green_statuses [:green, :pass, :passed, "green", "pass", "passed"]
  @preceding_proofs [
    {:gepa, :gepa_proof_ref, :gepa_status},
    {:trinity, :trinity_proof_ref, :trinity_status},
    {:adaptive_control, :adaptive_control_proof_ref, :adaptive_control_status}
  ]
  @live_required_refs [
    :tenant_ref,
    :authority_ref,
    :provider_account_ref,
    :model_profile_ref,
    :operation_policy_ref,
    :target_ref,
    :trace_ref
  ]
  @disposable_refs [:credential_lease_ref, :cleanup_ref]
  @openapi_usage_contexts [
    :tool_task,
    :eval_dataset_loader,
    :generated_sdk,
    :appkit_management_api
  ]
  @openapi_required_refs [
    :tenant_ref,
    :subject_ref,
    :provider_account_ref,
    :credential_lease_ref,
    :operation_policy_ref,
    :pristine_operation_ref,
    :connector_admission_ref,
    :trace_ref,
    :redaction_ref
  ]
  @graphql_required_bindings [
    :tenant_ref,
    :subject_ref,
    :provider_account_ref,
    :workspace_ref,
    :token_family_ref,
    :credential_lease_ref,
    :operation_policy_ref,
    :prismatic_operation_ref,
    :operation_name,
    :trace_ref,
    :redaction_ref
  ]
  @durable_profiles [:integration_postgres, :ops_durable, :full_debug_tracked]
  @durable_profile_names ["integration_postgres", "ops_durable", "full_debug_tracked"]
  @durable_preflight_refs [:migration_ref, :substrate_ref]
  @persistence_required_refs [
    :partition_ref,
    :retention_ref,
    :debug_tap_ref
  ]
  @debug_required_refs [:debug_tap_ref, :trace_ref]
  @forbidden_raw_keys [
    :api_key,
    :auth_header,
    :authorization_header,
    :credential_body,
    :memory_body,
    :model_output,
    :native_auth_file,
    :operator_private_payload,
    :provider_payload,
    :raw_model_output,
    :raw_payload,
    :raw_prompt,
    :raw_provider_payload,
    :secret,
    :token,
    :token_file,
    "api_key",
    "auth_header",
    "authorization_header",
    "credential_body",
    "memory_body",
    "model_output",
    "native_auth_file",
    "operator_private_payload",
    "provider_payload",
    "raw_model_output",
    "raw_payload",
    "raw_prompt",
    "raw_provider_payload",
    "secret",
    "token",
    "token_file"
  ]
  @known_string_keys %{
    "adaptive_control_proof_ref" => :adaptive_control_proof_ref,
    "adaptive_control_status" => :adaptive_control_status,
    "authority_ref" => :authority_ref,
    "capture_level" => :capture_level,
    "cleanup_ref" => :cleanup_ref,
    "connector_admission_ref" => :connector_admission_ref,
    "credential_lease_ref" => :credential_lease_ref,
    "debug_tap_ref" => :debug_tap_ref,
    "facts" => :facts,
    "gepa_proof_ref" => :gepa_proof_ref,
    "gepa_status" => :gepa_status,
    "migration_ref" => :migration_ref,
    "model_profile_ref" => :model_profile_ref,
    "operation_name" => :operation_name,
    "operation_policy_ref" => :operation_policy_ref,
    "partition_ref" => :partition_ref,
    "prismatic_operation_ref" => :prismatic_operation_ref,
    "pristine_operation_ref" => :pristine_operation_ref,
    "profile_id" => :profile_id,
    "provider_account_ref" => :provider_account_ref,
    "redaction_ref" => :redaction_ref,
    "retention_ref" => :retention_ref,
    "store_category" => :store_category,
    "subject_ref" => :subject_ref,
    "substrate_ref" => :substrate_ref,
    "target_ref" => :target_ref,
    "tenant_ref" => :tenant_ref,
    "token_family_ref" => :token_family_ref,
    "trace_ref" => :trace_ref,
    "trinity_proof_ref" => :trinity_proof_ref,
    "trinity_status" => :trinity_status,
    "usage_contexts" => :usage_contexts,
    "workspace_ref" => :workspace_ref
  }

  @spec live_provider_gate(map() | keyword()) :: {:ok, map()} | {:error, term()}
  def live_provider_gate(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_raw(attrs, :live_provider_raw_material_rejected),
         :ok <- require_preceding_proofs(attrs),
         :ok <- require_present(attrs, @disposable_refs, :missing_disposable_refs),
         :ok <- require_present(attrs, @live_required_refs, :missing_live_provider_refs) do
      {:ok,
       %{
         fixture_ref: "AOC-045",
         gate_ref: "live-provider-gate://phase14",
         tenant_ref: fetch!(attrs, :tenant_ref),
         authority_ref: fetch!(attrs, :authority_ref),
         provider_account_ref: fetch!(attrs, :provider_account_ref),
         model_profile_ref: fetch!(attrs, :model_profile_ref),
         operation_policy_ref: fetch!(attrs, :operation_policy_ref),
         credential_lease_ref: fetch!(attrs, :credential_lease_ref),
         cleanup_ref: fetch!(attrs, :cleanup_ref),
         target_ref: fetch!(attrs, :target_ref),
         trace_ref: fetch!(attrs, :trace_ref),
         preceding_proof_refs: preceding_proof_refs(attrs),
         live_network_required?: false,
         raw_material_present?: false
       }}
    end
  end

  @spec openapi_operation(map() | keyword()) :: {:ok, map()} | {:error, term()}
  def openapi_operation(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_raw(attrs, :openapi_raw_material_rejected),
         :ok <- require_present(attrs, @openapi_required_refs, :missing_openapi_refs),
         :ok <- require_openapi_usage_contexts(attrs) do
      {:ok,
       %{
         fixture_ref: "AOC-046",
         pristine_operation_ref: fetch!(attrs, :pristine_operation_ref),
         connector_admission_ref: fetch!(attrs, :connector_admission_ref),
         tenant_ref: fetch!(attrs, :tenant_ref),
         subject_ref: fetch!(attrs, :subject_ref),
         provider_account_ref: fetch!(attrs, :provider_account_ref),
         credential_lease_ref: fetch!(attrs, :credential_lease_ref),
         operation_policy_ref: fetch!(attrs, :operation_policy_ref),
         trace_ref: fetch!(attrs, :trace_ref),
         redaction_ref: fetch!(attrs, :redaction_ref),
         usage_contexts: @openapi_usage_contexts,
         governed_admission_required?: true,
         raw_material_present?: false
       }}
    end
  end

  @spec graphql_operation(map() | keyword()) :: {:ok, map()} | {:error, term()}
  def graphql_operation(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_raw(attrs, :graphql_raw_material_rejected),
         :ok <- require_present(attrs, @graphql_required_bindings, :missing_graphql_bindings) do
      {:ok,
       %{
         fixture_ref: "AOC-047",
         prismatic_operation_ref: fetch!(attrs, :prismatic_operation_ref),
         operation_name: fetch!(attrs, :operation_name),
         tenant_ref: fetch!(attrs, :tenant_ref),
         subject_ref: fetch!(attrs, :subject_ref),
         provider_account_ref: fetch!(attrs, :provider_account_ref),
         workspace_ref: fetch!(attrs, :workspace_ref),
         token_family_ref: fetch!(attrs, :token_family_ref),
         credential_lease_ref: fetch!(attrs, :credential_lease_ref),
         operation_policy_ref: fetch!(attrs, :operation_policy_ref),
         trace_ref: fetch!(attrs, :trace_ref),
         redaction_ref: fetch!(attrs, :redaction_ref),
         governed_admission_required?: true,
         raw_material_present?: false
       }}
    end
  end

  @spec persistence_profile(map() | keyword()) :: {:ok, map()} | {:error, term()}
  def persistence_profile(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)
    profile_id = Map.get(attrs, :profile_id, :mickey_mouse)

    with :ok <- reject_raw(attrs, :persistence_profile_raw_material_rejected),
         :ok <- durable_preflight(profile_id, attrs),
         :ok <- require_present(attrs, @persistence_required_refs, :missing_persistence_refs) do
      {:ok,
       %{
         fixture_ref: "PERSIST-AOC-006",
         profile_id: profile_id,
         store_category: Map.get(attrs, :store_category, :ai_run_envelope),
         selected_tier: selected_tier(profile_id),
         capture_level: Map.get(attrs, :capture_level, :minimal_refs),
         substrate_ref: Map.get(attrs, :substrate_ref),
         migration_ref: Map.get(attrs, :migration_ref),
         partition_ref: fetch!(attrs, :partition_ref),
         retention_ref: fetch!(attrs, :retention_ref),
         debug_tap_ref: fetch!(attrs, :debug_tap_ref),
         fail_closed_condition: :missing_substrate_or_migration,
         receipt_ref: "persistence-profile://phase14/#{profile_slug(profile_id)}",
         restart_safe?: durable_profile?(profile_id),
         raw_material_present?: false
       }}
    end
  end

  @spec debug_sidecar(map() | keyword()) :: {:ok, map()} | {:error, term()}
  def debug_sidecar(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_raw(attrs, :debug_sidecar_raw_material_rejected),
         :ok <- require_present(attrs, @debug_required_refs, :missing_debug_sidecar_refs) do
      {:ok,
       %{
         fixture_ref: "PERSIST-AOC-007",
         debug_sidecar_ref: "debug-sidecar://phase14/redacted",
         debug_tap_ref: fetch!(attrs, :debug_tap_ref),
         trace_ref: fetch!(attrs, :trace_ref),
         capture_level: :debug_redacted,
         facts: redacted_facts(Map.get(attrs, :facts, %{})),
         raw_material_present?: false
       }}
    end
  end

  defp normalize(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize()

  defp normalize(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key(key) when is_binary(key), do: Map.get(@known_string_keys, key, key)

  defp require_preceding_proofs(attrs) do
    missing =
      Enum.flat_map(@preceding_proofs, fn {proof, ref_key, status_key} ->
        if present?(Map.get(attrs, ref_key)) and Map.get(attrs, status_key) in @green_statuses do
          []
        else
          [proof]
        end
      end)

    if missing == [], do: :ok, else: {:error, {:missing_preceding_proofs, missing}}
  end

  defp preceding_proof_refs(attrs) do
    Enum.map(@preceding_proofs, fn {proof, ref_key, _status_key} ->
      {proof, fetch!(attrs, ref_key)}
    end)
  end

  defp require_openapi_usage_contexts(attrs) do
    contexts = Map.get(attrs, :usage_contexts, [])
    missing = Enum.reject(@openapi_usage_contexts, &(&1 in contexts))
    if missing == [], do: :ok, else: {:error, {:missing_openapi_usage_contexts, missing}}
  end

  defp durable_preflight(profile_id, attrs) do
    if durable_profile?(profile_id) do
      require_present(attrs, @durable_preflight_refs, :durable_profile_preflight_failed)
    else
      :ok
    end
  end

  defp selected_tier(:integration_postgres), do: :postgres
  defp selected_tier("integration_postgres"), do: :postgres
  defp selected_tier(:ops_durable), do: :durable
  defp selected_tier("ops_durable"), do: :durable
  defp selected_tier(:full_debug_tracked), do: :durable_debug
  defp selected_tier("full_debug_tracked"), do: :durable_debug
  defp selected_tier(_profile_id), do: :memory_ephemeral

  defp durable_profile?(profile_id)
       when is_atom(profile_id),
       do: profile_id in @durable_profiles

  defp durable_profile?(profile_id)
       when is_binary(profile_id),
       do: profile_id in @durable_profile_names

  defp durable_profile?(_profile_id), do: false

  defp profile_slug(profile_id) when is_atom(profile_id), do: Atom.to_string(profile_id)
  defp profile_slug(profile_id) when is_binary(profile_id), do: profile_id
  defp profile_slug(profile_id), do: inspect(profile_id)

  defp redacted_facts(facts) when is_map(facts) do
    Map.take(facts, [
      :summary_ref,
      :state_ref,
      :payload_hash_ref,
      "summary_ref",
      "state_ref",
      "payload_hash_ref"
    ])
  end

  defp redacted_facts(_facts), do: %{}

  defp require_present(attrs, keys, error_tag) do
    missing = Enum.reject(keys, &present?(Map.get(attrs, &1)))
    if missing == [], do: :ok, else: {:error, {error_tag, missing}}
  end

  defp reject_raw(attrs, error_tag) do
    case raw_key(attrs) do
      nil -> :ok
      key -> {:error, {error_tag, [key]}}
    end
  end

  defp raw_key(%_struct{} = value), do: value |> Map.from_struct() |> raw_key()

  defp raw_key(value) when is_map(value) do
    Enum.find_value(value, fn {key, nested} ->
      if key in @forbidden_raw_keys, do: key, else: raw_key(nested)
    end)
  end

  defp raw_key(values) when is_list(values), do: Enum.find_value(values, &raw_key/1)
  defp raw_key(_value), do: nil

  defp fetch!(attrs, key), do: Map.fetch!(attrs, key)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(value), do: not is_nil(value)
end
