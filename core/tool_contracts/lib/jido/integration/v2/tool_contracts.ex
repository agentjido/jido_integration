defmodule Jido.Integration.V2.ToolContracts do
  @moduledoc """
  Bounded ref-only tool contract descriptors.
  """

  @categories [
    :connector_tool,
    :host_tool,
    :mcp_external_tool,
    :operator_action,
    :product_action,
    :provider_native_tool,
    :read_only_observation,
    :synthetic_fixture_event
  ]

  @auth_sources [
    :authority_materialized,
    :connector_binding_ref,
    :none,
    :provider_native_assertion_ref,
    :read_only_ref
  ]

  @execution_authorities [
    :connector_operation,
    :host_runtime,
    :operator_control,
    :product_surface,
    :provider_native_runtime,
    :read_only_projection,
    :synthetic_fixture
  ]

  @redaction_classes [
    :event_metadata,
    :operator_metadata,
    :provider_tool_metadata,
    :ref_only,
    :synthetic_metadata
  ]

  @provider_operation_rows [
    %{
      provider: :github,
      family: "http",
      category: :connector_tool,
      operation: "github.issue.list"
    },
    %{
      provider: :linear,
      family: "graphql",
      category: :connector_tool,
      operation: "linear.issues.list"
    },
    %{
      provider: :notion,
      family: "http",
      category: :connector_tool,
      operation: "notion.page.search"
    },
    %{
      provider: :reqllm_next,
      family: "realtime",
      category: :provider_native_tool,
      operation: "reqllm_next.response.stream"
    },
    %{
      provider: :inference,
      family: "inference",
      category: :provider_native_tool,
      operation: "inference.run"
    },
    %{provider: :codex, family: "cli", category: :host_tool, operation: "codex.session.turn"},
    %{provider: :claude, family: "cli", category: :host_tool, operation: "claude.session.turn"},
    %{provider: :gemini, family: "cli", category: :host_tool, operation: "gemini.session.turn"},
    %{
      provider: :amp,
      family: "cli",
      category: :provider_native_tool,
      operation: "amp.command.run"
    }
  ]

  @operation_required_refs [
    :tenant_ref,
    :installation_ref,
    :trace_ref,
    :provider_account_ref,
    :connector_instance_ref,
    :connector_binding_ref,
    :operation_policy_ref,
    :credential_handle_ref,
    :credential_lease_ref,
    :target_ref,
    :connector_admission_ref
  ]

  @operation_ref_prefixes %{
    tenant_ref: "tenant://",
    installation_ref: "installation://",
    trace_ref: "trace://",
    provider_account_ref: "provider-account://",
    connector_instance_ref: "connector-instance://",
    connector_binding_ref: "connector-binding://",
    operation_policy_ref: "operation-policy://",
    credential_handle_ref: "credential-handle://",
    credential_lease_ref: "credential-lease://",
    target_ref: "target://",
    connector_admission_ref: "connector-admission://"
  }

  @operation_identity_refs [
    :installation_ref,
    :trace_ref,
    :provider_account_ref,
    :connector_instance_ref,
    :connector_binding_ref,
    :operation_policy_ref,
    :credential_handle_ref,
    :credential_lease_ref,
    :target_ref,
    :connector_admission_ref
  ]

  @multi_operation_keys [
    :operation_ids,
    :operations,
    :requested_operations
  ]

  @category_sandbox %{
    connector_tool: "strict",
    host_tool: "strict",
    mcp_external_tool: "external_governed",
    operator_action: "operator_only",
    product_action: "product_boundary",
    provider_native_tool: "strict",
    read_only_observation: "read_only",
    synthetic_fixture_event: "fixture_only"
  }

  @forbidden_keys [
    :api_key,
    :auth_root,
    :authorization_header,
    :command_secret,
    :config_root,
    :cwd,
    :env,
    :hidden_authority,
    :provider_api_key,
    :provider_payload,
    :raw_token,
    :shell_args,
    :target_credentials,
    :token,
    :token_file
  ]

  @enforce_keys [
    :contract_ref,
    :category,
    :auth_source,
    :execution_authority,
    :redaction_class,
    :allowed_payload_keys
  ]
  defstruct @enforce_keys ++ [metadata: %{}]

  defmodule OperationBinding do
    @moduledoc """
    Ref-only tool operation binding used before provider effects.
    """

    @enforce_keys [
      :tool_ref,
      :contract_ref,
      :category,
      :provider_family,
      :requested_operation,
      :tool_sandbox,
      :tenant_ref,
      :installation_ref,
      :trace_ref,
      :provider_account_ref,
      :connector_instance_ref,
      :connector_binding_ref,
      :operation_policy_ref,
      :credential_handle_ref,
      :credential_lease_ref,
      :target_ref,
      :connector_admission_ref,
      :redaction_class
    ]

    defstruct @enforce_keys ++
                [
                  allowed_payload_keys: [],
                  payload: %{},
                  rejection_reason: nil,
                  raw_material_present?: false
                ]

    @type t :: %__MODULE__{
            tool_ref: String.t(),
            contract_ref: String.t(),
            category: atom(),
            provider_family: String.t(),
            requested_operation: String.t(),
            tool_sandbox: String.t(),
            tenant_ref: String.t(),
            installation_ref: String.t(),
            trace_ref: String.t(),
            provider_account_ref: String.t(),
            connector_instance_ref: String.t(),
            connector_binding_ref: String.t(),
            operation_policy_ref: String.t(),
            credential_handle_ref: String.t(),
            credential_lease_ref: String.t(),
            target_ref: String.t(),
            connector_admission_ref: String.t(),
            redaction_class: atom(),
            allowed_payload_keys: [String.t()],
            payload: map(),
            rejection_reason: term(),
            raw_material_present?: false
          }
  end

  @type t :: %__MODULE__{
          contract_ref: String.t(),
          category: atom(),
          auth_source: atom(),
          execution_authority: atom(),
          redaction_class: atom(),
          allowed_payload_keys: [String.t()],
          metadata: map()
        }

  @spec categories() :: [atom()]
  def categories, do: @categories

  @spec forbidden_keys() :: [atom()]
  def forbidden_keys, do: @forbidden_keys

  @spec operation_required_refs() :: [atom()]
  def operation_required_refs, do: @operation_required_refs

  @spec provider_operation_rows() :: [map()]
  def provider_operation_rows, do: @provider_operation_rows

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_forbidden(attrs),
         {:ok, category} <- enum_value(attrs, :category, @categories),
         {:ok, auth_source} <- enum_value(attrs, :auth_source, @auth_sources),
         {:ok, execution_authority} <-
           enum_value(attrs, :execution_authority, @execution_authorities),
         {:ok, redaction_class} <- enum_value(attrs, :redaction_class, @redaction_classes),
         {:ok, keys} <- allowed_payload_keys(value(attrs, :allowed_payload_keys)) do
      {:ok,
       %__MODULE__{
         contract_ref: string!(attrs, :contract_ref),
         category: category,
         auth_source: auth_source,
         execution_authority: execution_authority,
         redaction_class: redaction_class,
         allowed_payload_keys: keys,
         metadata: metadata(attrs)
       }}
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec bind_operation(map() | keyword()) :: {:ok, OperationBinding.t()} | {:error, term()}
  def bind_operation(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)
    payload = payload(attrs)

    with :ok <- reject_forbidden(attrs),
         :ok <- reject_payload_forbidden(payload),
         :ok <- reject_multi_operation(attrs, payload),
         :ok <- require_operation_refs(attrs),
         :ok <- validate_ref_prefixes(attrs),
         {:ok, category} <- enum_value(attrs, :category, @categories),
         {:ok, operation_row} <- operation_row(attrs, category),
         :ok <- validate_sandbox(attrs, category),
         :ok <- validate_operation_identity(attrs, operation_row),
         {:ok, redaction_class} <- enum_value(attrs, :redaction_class, @redaction_classes),
         {:ok, keys} <- allowed_payload_keys(value(attrs, :allowed_payload_keys)),
         :ok <- validate_payload_keys(payload, keys) do
      {:ok,
       %OperationBinding{
         tool_ref: string!(attrs, :tool_ref),
         contract_ref: string!(attrs, :contract_ref),
         category: category,
         provider_family: string!(attrs, :provider_family),
         requested_operation: string!(attrs, :requested_operation),
         tool_sandbox: sandbox_name(value(attrs, :tool_sandbox)),
         tenant_ref: string!(attrs, :tenant_ref),
         installation_ref: string!(attrs, :installation_ref),
         trace_ref: string!(attrs, :trace_ref),
         provider_account_ref: string!(attrs, :provider_account_ref),
         connector_instance_ref: string!(attrs, :connector_instance_ref),
         connector_binding_ref: string!(attrs, :connector_binding_ref),
         operation_policy_ref: string!(attrs, :operation_policy_ref),
         credential_handle_ref: string!(attrs, :credential_handle_ref),
         credential_lease_ref: string!(attrs, :credential_lease_ref),
         target_ref: string!(attrs, :target_ref),
         connector_admission_ref: string!(attrs, :connector_admission_ref),
         redaction_class: redaction_class,
         allowed_payload_keys: keys,
         payload: payload,
         raw_material_present?: false
       }}
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec operation_result_receipt(OperationBinding.t(), map() | keyword()) ::
          {:ok, map()} | {:error, term()}
  def operation_result_receipt(%OperationBinding{} = binding, attrs)
      when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_result_material(attrs) do
      {:ok,
       %{
         tool_ref: binding.tool_ref,
         contract_ref: binding.contract_ref,
         requested_operation: binding.requested_operation,
         trace_ref: binding.trace_ref,
         target_ref: binding.target_ref,
         connector_admission_ref: binding.connector_admission_ref,
         redaction_class: binding.redaction_class,
         result_ref: result_ref(binding),
         raw_material_present?: false,
         provider_payload_redacted?: true
       }}
    end
  end

  @spec summary(t()) :: map()
  def summary(%__MODULE__{} = contract) do
    %{
      contract_ref: contract.contract_ref,
      category: contract.category,
      auth_source: contract.auth_source,
      execution_authority: contract.execution_authority,
      redaction_class: contract.redaction_class,
      allowed_payload_keys: contract.allowed_payload_keys,
      metadata: contract.metadata
    }
  end

  defp normalize(attrs) when is_map(attrs), do: attrs
  defp normalize(attrs) when is_list(attrs), do: Map.new(attrs)

  defp reject_forbidden(attrs) do
    forbidden =
      @forbidden_keys
      |> Enum.filter(fn key -> has_key?(attrs, key) or has_key?(metadata(attrs), key) end)

    if forbidden == [] do
      :ok
    else
      {:error, {:forbidden_tool_contract_fields, forbidden}}
    end
  end

  defp reject_payload_forbidden(payload) do
    forbidden = Enum.filter(@forbidden_keys, &has_key?(payload, &1))

    if forbidden == [] do
      :ok
    else
      {:error, {:forbidden_tool_payload_fields, forbidden}}
    end
  end

  defp reject_multi_operation(attrs, payload) do
    fields =
      @multi_operation_keys
      |> Enum.filter(fn key -> multi_operation_field?(value(attrs, key)) end)
      |> Kernel.++(
        Enum.filter(@multi_operation_keys, fn key ->
          multi_operation_field?(value(payload, key))
        end)
      )
      |> Enum.uniq()

    case fields do
      [] -> :ok
      keys -> {:error, {:multi_tool_operation_rejected, keys}}
    end
  end

  defp multi_operation_field?([_first, _second | _rest]), do: true
  defp multi_operation_field?(_value), do: false

  defp require_operation_refs(attrs) do
    missing = Enum.reject(@operation_required_refs, &present?(value(attrs, &1)))

    case missing do
      [] -> :ok
      fields -> {:error, {:missing_tool_operation_refs, fields}}
    end
  end

  defp validate_ref_prefixes(attrs) do
    mismatched =
      @operation_ref_prefixes
      |> Enum.filter(fn {field, prefix} ->
        current = value(attrs, field)
        present?(current) and not String.starts_with?(current, prefix)
      end)
      |> Enum.map(fn {field, _prefix} -> field end)

    case mismatched do
      [] -> :ok
      fields -> {:error, {:tool_operation_ref_mismatch, fields}}
    end
  end

  defp operation_row(attrs, category) do
    requested_operation = value(attrs, :requested_operation)
    provider_family = value(attrs, :provider_family)

    case Enum.find(@provider_operation_rows, fn row ->
           row.operation == requested_operation and
             row.family == provider_family and
             row.category == category
         end) do
      nil ->
        {:error,
         {:unsupported_tool_mode,
          %{
            requested_operation: requested_operation,
            provider_family: provider_family,
            category: category
          }}}

      row ->
        {:ok, row}
    end
  end

  defp validate_sandbox(attrs, category) do
    expected = Map.fetch!(@category_sandbox, category)

    case sandbox_name(value(attrs, :tool_sandbox)) do
      ^expected -> :ok
      current -> {:error, {:tool_sandbox_mismatch, %{expected: expected, got: current}}}
    end
  end

  defp validate_operation_identity(attrs, row) do
    expected_provider = Atom.to_string(row.provider)

    with :ok <- validate_tenant_identity(attrs),
         :ok <- validate_provider_identity(attrs, expected_provider) do
      validate_family_identity(attrs, row.family)
    end
  end

  defp validate_tenant_identity(attrs) do
    tenant = ref_tail(value(attrs, :tenant_ref), :tenant_ref)

    bad =
      @operation_identity_refs
      |> Enum.filter(fn field ->
        case ref_segments(value(attrs, field), field) do
          [^tenant | _rest] -> false
          _other -> true
        end
      end)

    case bad do
      [] -> :ok
      fields -> {:error, {:tenant_ref_mismatch, fields}}
    end
  end

  defp validate_provider_identity(attrs, expected_provider) do
    bad =
      @operation_identity_refs
      |> Enum.filter(fn field ->
        case ref_segments(value(attrs, field), field) do
          [_tenant, ^expected_provider | _rest] -> false
          _other -> true
        end
      end)

    case bad do
      [] -> :ok
      fields -> {:error, {:provider_ref_mismatch, fields}}
    end
  end

  defp validate_family_identity(attrs, expected_family) do
    bad =
      @operation_identity_refs
      |> Enum.filter(fn field ->
        case ref_segments(value(attrs, field), field) do
          [_tenant, _provider, ^expected_family | _rest] -> false
          _other -> true
        end
      end)

    cond do
      bad == [] ->
        :ok

      :target_ref in bad ->
        {:error, {:target_ref_mismatch, bad}}

      true ->
        {:error, {:token_family_ref_mismatch, bad}}
    end
  end

  defp reject_result_material(attrs) do
    forbidden =
      @forbidden_keys
      |> Enum.filter(fn key -> has_key?(attrs, key) or has_key?(payload(attrs), key) end)

    case forbidden do
      [] -> :ok
      fields -> {:error, {:forbidden_tool_result_fields, fields}}
    end
  end

  defp enum_value(attrs, field, allowed) do
    current = value(attrs, field)

    if current in allowed do
      {:ok, current}
    else
      {:error, {:invalid_tool_contract_enum, field, current, allowed}}
    end
  end

  defp allowed_payload_keys(keys) when is_list(keys) do
    if Enum.all?(keys, &valid_payload_key?/1) do
      {:ok, keys}
    else
      {:error, {:invalid_allowed_payload_keys, keys}}
    end
  end

  defp allowed_payload_keys(keys), do: {:error, {:invalid_allowed_payload_keys, keys}}

  defp valid_payload_key?(key), do: is_binary(key) and key != ""

  defp validate_payload_keys(payload, allowed) do
    unknown =
      payload
      |> Map.keys()
      |> Enum.map(&key_name/1)
      |> Enum.reject(&(&1 in allowed))

    case unknown do
      [] -> :ok
      keys -> {:error, {:undeclared_tool_payload_keys, keys}}
    end
  end

  defp string!(attrs, field) do
    case value(attrs, field) do
      current when is_binary(current) and current != "" ->
        current

      current ->
        raise ArgumentError, "#{field} must be a non-empty string, got: #{inspect(current)}"
    end
  end

  defp metadata(attrs) do
    case value(attrs, :metadata) do
      %{} = metadata -> metadata
      _other -> %{}
    end
  end

  defp payload(attrs) do
    case value(attrs, :payload) do
      %{} = current -> current
      nil -> %{}
      current -> raise ArgumentError, "payload must be a map, got: #{inspect(current)}"
    end
  end

  defp result_ref(%OperationBinding{} = binding) do
    tail =
      [
        ref_tail(binding.tenant_ref, :tenant_ref),
        operation_provider(binding),
        binding.provider_family,
        binding.requested_operation
      ]
      |> Enum.join("/")

    "tool-result://" <> tail
  end

  defp operation_provider(%OperationBinding{} = binding) do
    binding.provider_account_ref
    |> ref_segments(:provider_account_ref)
    |> Enum.at(1)
  end

  defp ref_tail(ref, field) do
    ref
    |> ref_segments(field)
    |> List.first()
  end

  defp ref_segments(ref, field) when is_binary(ref) do
    prefix = Map.fetch!(@operation_ref_prefixes, field)

    ref
    |> String.replace_prefix(prefix, "")
    |> String.split("/", trim: true)
  end

  defp ref_segments(_ref, _field), do: []

  defp sandbox_name(value) when is_atom(value), do: Atom.to_string(value)
  defp sandbox_name(value) when is_binary(value), do: value
  defp sandbox_name(_value), do: nil

  defp value(attrs, field) do
    Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field))
  end

  defp has_key?(attrs, field) when is_map(attrs) do
    Map.has_key?(attrs, field) or Map.has_key?(attrs, Atom.to_string(field))
  end

  defp key_name(key) when is_atom(key), do: Atom.to_string(key)
  defp key_name(key) when is_binary(key), do: key
  defp key_name(key), do: inspect(key)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
end
