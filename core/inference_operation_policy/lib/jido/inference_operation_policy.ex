defmodule Jido.InferenceOperationPolicy do
  @moduledoc """
  Governed operation-policy binding for model calls.
  """

  @operation_classes [
    :propose,
    :evaluate,
    :route,
    :verify,
    :embed,
    :rerank,
    :summarize,
    :reflect,
    :tool_call,
    :context_compact,
    :memory_query,
    :memory_write
  ]

  @required_fields [
    :operation_policy_ref,
    :tenant_ref,
    :authority_ref,
    :allowed_operations,
    :model_profile_refs,
    :capability_requirements,
    :budget_ref,
    :target_ref
  ]

  @request_required_fields [:tenant_ref, :authority_ref, :operation_class, :model_profile_ref]

  @forbidden_material [
    :api_key,
    :authorization_header,
    :default_client,
    :env,
    :provider_payload,
    :raw_model_output,
    :raw_prompt,
    :raw_provider_payload,
    :raw_secret,
    :raw_token,
    :standalone_auth,
    :token,
    :token_file
  ]

  @provider_default_fields [:default_model, :provider_default, :provider_default_model]

  defstruct @required_fields ++ [raw_material_present?: false]

  @type t :: %__MODULE__{}

  @spec operation_classes() :: [atom()]
  def operation_classes, do: @operation_classes

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_material(attrs),
         :ok <- require_fields(attrs, @required_fields, :missing_policy_refs),
         :ok <- validate_allowed_operations(attrs),
         :ok <- validate_model_profile_refs(attrs) do
      {:ok, struct!(__MODULE__, Map.take(attrs, @required_fields))}
    end
  end

  @spec authorize(map() | keyword(), t()) :: {:ok, map()} | {:error, term()}
  def authorize(request, %__MODULE__{} = policy) when is_map(request) or is_list(request) do
    request = normalize(request)

    with :ok <- reject_provider_defaults(request),
         :ok <- reject_material(request),
         :ok <- require_fields(request, @request_required_fields, :missing_request_refs),
         :ok <- validate_scope(request, policy),
         :ok <- validate_operation(request, policy),
         :ok <- validate_model_profile(request, policy),
         :ok <- validate_capabilities(request, policy) do
      {:ok, authorization_receipt(request, policy)}
    end
  end

  defp normalize(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize()

  defp normalize(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    candidates =
      @required_fields ++
        @request_required_fields ++ @forbidden_material ++ @provider_default_fields

    Enum.find(candidates, key, &(Atom.to_string(&1) == key))
  end

  defp reject_material(attrs) do
    rejected = Enum.filter(@forbidden_material, &Map.has_key?(attrs, &1))
    if rejected == [], do: :ok, else: {:error, {:raw_material_rejected, rejected}}
  end

  defp reject_provider_defaults(attrs) do
    case Enum.find(@provider_default_fields, &Map.has_key?(attrs, &1)) do
      nil -> :ok
      field -> {:error, {:provider_default_rejected, field}}
    end
  end

  defp require_fields(attrs, fields, error_tag) do
    missing = Enum.reject(fields, &present?(Map.get(attrs, &1)))
    if missing == [], do: :ok, else: {:error, {error_tag, missing}}
  end

  defp validate_allowed_operations(attrs) do
    allowed = Map.fetch!(attrs, :allowed_operations)

    invalid =
      allowed
      |> List.wrap()
      |> Enum.reject(&(&1 in @operation_classes))

    if invalid == [], do: :ok, else: {:error, {:unknown_operation_classes, invalid}}
  end

  defp validate_model_profile_refs(attrs) do
    model_profile_refs = Map.fetch!(attrs, :model_profile_refs)

    if is_list(model_profile_refs) and model_profile_refs != [] do
      :ok
    else
      {:error, {:missing_policy_refs, [:model_profile_refs]}}
    end
  end

  defp validate_scope(request, policy) do
    cond do
      request.tenant_ref != policy.tenant_ref ->
        {:error, {:tenant_mismatch, request.tenant_ref}}

      request.authority_ref != policy.authority_ref ->
        {:error, {:authority_mismatch, request.authority_ref}}

      true ->
        :ok
    end
  end

  defp validate_operation(request, policy) do
    if request.operation_class in policy.allowed_operations do
      :ok
    else
      {:error, {:operation_not_allowed, request.operation_class}}
    end
  end

  defp validate_model_profile(request, policy) do
    if request.model_profile_ref in policy.model_profile_refs do
      :ok
    else
      {:error, {:model_profile_not_allowed, request.model_profile_ref}}
    end
  end

  defp validate_capabilities(request, policy) do
    requirements = Map.get(policy.capability_requirements, request.operation_class, [])
    capability_set = Map.get(request, :capability_set, [])

    missing = Enum.reject(requirements, &(&1 in capability_set))
    if missing == [], do: :ok, else: {:error, {:missing_capabilities, missing}}
  end

  defp authorization_receipt(request, policy) do
    %{
      operation_policy_ref: policy.operation_policy_ref,
      tenant_ref: policy.tenant_ref,
      authority_ref: policy.authority_ref,
      operation_class: request.operation_class,
      model_profile_ref: request.model_profile_ref,
      budget_ref: policy.budget_ref,
      target_ref: policy.target_ref,
      raw_material_present?: false
    }
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(value) when is_map(value), do: true
  defp present?(value), do: not is_nil(value)
end
