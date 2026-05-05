defmodule Jido.Integration.V2.ConnectorRegistry do
  @moduledoc """
  Minimal ref-only connector registry for provider identity selection.
  """

  @connector_categories [
    :official_connector,
    :companion_connector,
    :generated_sdk_client,
    :provider_cli_adapter,
    :app_connector
  ]

  @provider_families [
    "cli",
    "http",
    "graphql",
    "realtime",
    "inference",
    "service_runtime",
    "app_server"
  ]

  @provider_account_statuses [
    :known,
    :asserted,
    :unknown,
    :unavailable,
    :revoked,
    :rotated
  ]

  @env_remediation_states [
    :not_applicable,
    :standalone_only,
    :governed_clean,
    :open_defect
  ]

  @required_refs [
    :tenant_ref,
    :policy_revision_ref,
    :provider_ref,
    :provider_family,
    :provider_account_ref,
    :provider_account_status,
    :connector_ref,
    :connector_instance_ref,
    :connector_binding_ref,
    :connector_category,
    :credential_handle_ref,
    :target_ref,
    :operation_policy_ref,
    :owner_repo,
    :package_path,
    :conformance_suite_ref,
    :env_remediation_state
  ]

  @forbidden_material [
    :api_key,
    :auth_json,
    :authorization_header,
    :default_client,
    :env,
    :native_auth_file,
    :provider_payload,
    :raw_secret,
    :raw_token,
    :singleton_client,
    :target_credentials,
    :token,
    :token_file
  ]

  @ref_prefixes %{
    tenant_ref: "tenant://",
    policy_revision_ref: "policy-revision://",
    provider_ref: "provider://",
    provider_account_ref: "provider-account://",
    connector_ref: "connector://",
    connector_instance_ref: "connector-instance://",
    connector_binding_ref: "connector-binding://",
    credential_handle_ref: "credential-handle://",
    target_ref: "target://",
    operation_policy_ref: "operation-policy://",
    conformance_suite_ref: "conformance-suite://"
  }

  defmodule Entry do
    @moduledoc false

    @entry_fields [
      :tenant_ref,
      :policy_revision_ref,
      :provider_ref,
      :provider_family,
      :provider_account_ref,
      :provider_account_status,
      :connector_ref,
      :connector_instance_ref,
      :connector_binding_ref,
      :connector_category,
      :credential_handle_ref,
      :target_ref,
      :operation_policy_ref,
      :owner_repo,
      :package_path,
      :conformance_suite_ref,
      :env_remediation_state
    ]

    @enforce_keys @entry_fields
    defstruct @entry_fields ++
                [
                  auth_methods: [],
                  supported_operations: [],
                  target_refs: [],
                  credential_handle_refs: [],
                  binding_shape: %{},
                  product_boundary: %{},
                  registry_schema: "Jido.Integration.V2.ConnectorRegistry.Entry.v1"
                ]
  end

  @type entry :: %Entry{}

  @spec connector_categories() :: [atom()]
  def connector_categories, do: @connector_categories

  @spec provider_families() :: [String.t()]
  def provider_families, do: @provider_families

  @spec provider_account_statuses() :: [atom()]
  def provider_account_statuses, do: @provider_account_statuses

  @spec env_remediation_states() :: [atom()]
  def env_remediation_states, do: @env_remediation_states

  @spec required_refs() :: [atom()]
  def required_refs, do: @required_refs

  @spec register(map() | keyword()) :: {:ok, entry()} | {:error, term()}
  def register(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_material(attrs),
         :ok <- require_refs(attrs, @required_refs),
         :ok <- validate_ref_families(attrs),
         :ok <- validate_distinct_refs(attrs),
         {:ok, category} <- enum_value(attrs, :connector_category, @connector_categories),
         {:ok, status} <- enum_value(attrs, :provider_account_status, @provider_account_statuses),
         {:ok, env_state} <- enum_value(attrs, :env_remediation_state, @env_remediation_states),
         :ok <- validate_provider_family(attrs) do
      {:ok,
       %Entry{
         tenant_ref: value!(attrs, :tenant_ref),
         policy_revision_ref: value!(attrs, :policy_revision_ref),
         provider_ref: value!(attrs, :provider_ref),
         provider_family: value!(attrs, :provider_family),
         provider_account_ref: value!(attrs, :provider_account_ref),
         provider_account_status: status,
         connector_ref: value!(attrs, :connector_ref),
         connector_instance_ref: value!(attrs, :connector_instance_ref),
         connector_binding_ref: value!(attrs, :connector_binding_ref),
         connector_category: category,
         credential_handle_ref: value!(attrs, :credential_handle_ref),
         target_ref: value!(attrs, :target_ref),
         operation_policy_ref: value!(attrs, :operation_policy_ref),
         owner_repo: value!(attrs, :owner_repo),
         package_path: value!(attrs, :package_path),
         conformance_suite_ref: value!(attrs, :conformance_suite_ref),
         env_remediation_state: env_state,
         auth_methods: list_field(attrs, :auth_methods),
         supported_operations: list_field(attrs, :supported_operations),
         target_refs: list_field(attrs, :target_refs),
         credential_handle_refs:
           list_field(attrs, :credential_handle_refs, [value!(attrs, :credential_handle_ref)]),
         binding_shape: map_field(attrs, :binding_shape),
         product_boundary: map_field(attrs, :product_boundary)
       }}
    end
  end

  @spec select_credential([entry()], map() | keyword()) :: {:ok, entry()} | {:error, term()}
  def select_credential(entries, attrs)
      when is_list(entries) and (is_map(attrs) or is_list(attrs)) do
    attrs = normalize(attrs)
    required = selection_required_refs()

    with :ok <- require_refs(attrs, required),
         :ok <- validate_ref_families(attrs, required) do
      matches =
        Enum.filter(entries, fn
          %Entry{} = entry -> selection_match?(entry, attrs)
          _other -> false
        end)

      case matches do
        [entry] -> {:ok, entry}
        [] -> {:error, :credential_selection_not_found}
        _many -> {:error, :credential_selection_ambiguous}
      end
    end
  end

  @spec identity_key(entry()) :: map()
  def identity_key(%Entry{} = entry) do
    %{
      tenant_ref: entry.tenant_ref,
      policy_revision_ref: entry.policy_revision_ref,
      provider_ref: entry.provider_ref,
      provider_account_ref: entry.provider_account_ref,
      connector_instance_ref: entry.connector_instance_ref,
      connector_binding_ref: entry.connector_binding_ref,
      credential_handle_ref: entry.credential_handle_ref,
      target_ref: entry.target_ref,
      operation_policy_ref: entry.operation_policy_ref
    }
  end

  @spec companion_admission(entry()) :: {:ok, map()} | {:error, term()}
  def companion_admission(%Entry{} = entry) do
    if entry.connector_category in [:companion_connector, :generated_sdk_client] do
      {:ok,
       %{
         admission_ref: companion_admission_ref(entry),
         provider_ref: entry.provider_ref,
         provider_family: entry.provider_family,
         connector_ref: entry.connector_ref,
         connector_instance_ref: entry.connector_instance_ref,
         connector_binding_ref: entry.connector_binding_ref,
         connector_category: entry.connector_category,
         owner_repo: entry.owner_repo,
         package_path: entry.package_path,
         credential_handle_ref: entry.credential_handle_ref,
         target_ref: entry.target_ref,
         operation_policy_ref: entry.operation_policy_ref,
         conformance_suite_ref: entry.conformance_suite_ref,
         env_remediation_state: entry.env_remediation_state,
         binding_shape: entry.binding_shape,
         product_boundary: entry.product_boundary
       }}
    else
      {:error, {:not_companion_lane, entry.connector_category}}
    end
  end

  @spec upgrade_to_official(entry(), map() | keyword()) :: {:ok, entry()} | {:error, term()}
  def upgrade_to_official(%Entry{} = entry, attrs) when is_map(attrs) or is_list(attrs) do
    entry
    |> Map.from_struct()
    |> Map.merge(normalize(attrs))
    |> Map.put(:connector_category, :official_connector)
    |> register()
  end

  defp selection_required_refs do
    [
      :tenant_ref,
      :policy_revision_ref,
      :provider_ref,
      :provider_account_ref,
      :connector_instance_ref,
      :connector_binding_ref,
      :credential_handle_ref,
      :target_ref,
      :operation_policy_ref
    ]
  end

  defp selection_match?(%Entry{} = entry, attrs) do
    Enum.all?(selection_required_refs(), fn field ->
      Map.fetch!(identity_key(entry), field) == field_value(attrs, field)
    end)
  end

  defp normalize(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize()

  defp normalize(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    candidates =
      @required_refs ++
        @forbidden_material ++
        [
          :auth_methods,
          :supported_operations,
          :target_refs,
          :credential_handle_refs,
          :binding_shape,
          :product_boundary
        ]

    Enum.find(candidates, key, fn candidate -> Atom.to_string(candidate) == key end)
  end

  defp reject_material(attrs) do
    case Enum.filter(@forbidden_material, &Map.has_key?(attrs, &1)) do
      [] -> :ok
      fields -> {:error, {:raw_material_rejected, fields}}
    end
  end

  defp require_refs(attrs, fields) do
    case Enum.reject(fields, &present?(field_value(attrs, &1))) do
      [] -> :ok
      missing -> {:error, {:missing_selection_refs, missing}}
    end
  end

  defp validate_ref_families(attrs, fields \\ @required_refs) do
    bad =
      fields
      |> Enum.filter(fn field ->
        case Map.fetch(@ref_prefixes, field) do
          {:ok, prefix} ->
            value = field_value(attrs, field)
            present?(value) and not String.starts_with?(value, prefix)

          :error ->
            false
        end
      end)

    case bad do
      [] -> :ok
      fields -> {:error, {:ref_family_mismatch, fields}}
    end
  end

  defp validate_distinct_refs(attrs) do
    comparisons = [
      {:provider_account_ref, :connector_instance_ref},
      {:provider_account_ref, :connector_binding_ref},
      {:provider_account_ref, :credential_handle_ref},
      {:connector_instance_ref, :connector_binding_ref},
      {:connector_instance_ref, :credential_handle_ref},
      {:connector_binding_ref, :credential_handle_ref}
    ]

    conflicts =
      Enum.filter(comparisons, fn {left, right} ->
        field_value(attrs, left) == field_value(attrs, right)
      end)

    case conflicts do
      [] -> :ok
      pairs -> {:error, {:ref_conflation_rejected, pairs}}
    end
  end

  defp enum_value(attrs, field, allowed) do
    value = field_value(attrs, field)

    cond do
      is_atom(value) and value in allowed ->
        {:ok, value}

      is_binary(value) ->
        case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
          nil -> {:error, {:invalid_enum_value, field, value, allowed}}
          atom -> {:ok, atom}
        end

      true ->
        {:error, {:invalid_enum_value, field, value, allowed}}
    end
  end

  defp validate_provider_family(attrs) do
    value = field_value(attrs, :provider_family)

    if value in @provider_families do
      :ok
    else
      {:error, {:unsupported_provider_family, value}}
    end
  end

  defp value!(attrs, field) do
    case field_value(attrs, field) do
      value when is_binary(value) and value != "" -> value
      value -> raise ArgumentError, "#{field} must be present, got: #{inspect(value)}"
    end
  end

  defp list_field(attrs, field, default \\ []) do
    case field_value(attrs, field) do
      value when is_list(value) -> value
      _value -> default
    end
  end

  defp map_field(attrs, field) do
    case field_value(attrs, field) do
      value when is_map(value) -> value
      _value -> %{}
    end
  end

  defp field_value(attrs, field),
    do: Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field))

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(value), do: not is_nil(value)

  defp companion_admission_ref(%Entry{} = entry) do
    Enum.join(
      [
        "connector-admission://",
        entry.tenant_ref,
        entry.owner_repo,
        entry.package_path,
        Atom.to_string(entry.connector_category)
      ],
      "/"
    )
  end
end
