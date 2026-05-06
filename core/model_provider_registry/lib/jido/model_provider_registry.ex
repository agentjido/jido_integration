defmodule Jido.ModelProviderRegistry do
  @moduledoc """
  Governed model/provider materialization registry.
  """

  alias Jido.ModelProviderRegistry.CapabilityMatrix

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
    :tenant_ref,
    :model_profile_ref,
    :provider_ref,
    :endpoint_profile_ref,
    :authority_ref,
    :operation_policy_ref,
    :operation_class,
    :capability_set,
    :cost_profile_ref,
    :context_window_ref,
    :retention_posture_ref,
    :materialization_posture
  ]

  @forbidden_material [
    :api_key,
    :auth_json,
    :authorization_header,
    :default_client,
    :default_model,
    :env,
    :native_auth_file,
    :provider_defaults,
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

  @spec operation_classes() :: [atom()]
  def operation_classes, do: @operation_classes

  @spec materialize(map() | keyword()) :: {:ok, map()} | {:error, term()}
  def materialize(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_material(attrs),
         :ok <- require_fields(attrs),
         :ok <- validate_operation_class(attrs),
         {:ok, capabilities} <- CapabilityMatrix.validate(Map.fetch!(attrs, :capability_set)) do
      {:ok, materialization_receipt(attrs, capabilities)}
    end
  end

  defp normalize(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize()

  defp normalize(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {normalize_key(key), value} end)
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    candidates = @required_fields ++ @forbidden_material
    Enum.find(candidates, key, &(Atom.to_string(&1) == key))
  end

  defp reject_material(attrs) do
    rejected = Enum.filter(@forbidden_material, &Map.has_key?(attrs, &1))
    if rejected == [], do: :ok, else: {:error, {:raw_material_rejected, rejected}}
  end

  defp require_fields(attrs) do
    missing = Enum.reject(@required_fields, &present?(Map.get(attrs, &1)))
    if missing == [], do: :ok, else: {:error, {:missing_materialization_refs, missing}}
  end

  defp validate_operation_class(attrs) do
    operation_class = Map.fetch!(attrs, :operation_class)

    if operation_class in @operation_classes do
      :ok
    else
      {:error, {:unknown_operation_class, operation_class}}
    end
  end

  defp materialization_receipt(attrs, capabilities) do
    %{
      materialization_ref: materialization_ref(attrs, capabilities),
      tenant_ref: Map.fetch!(attrs, :tenant_ref),
      model_profile_ref: Map.fetch!(attrs, :model_profile_ref),
      provider_ref: Map.fetch!(attrs, :provider_ref),
      endpoint_profile_ref: Map.fetch!(attrs, :endpoint_profile_ref),
      authority_ref: Map.fetch!(attrs, :authority_ref),
      operation_policy_ref: Map.fetch!(attrs, :operation_policy_ref),
      operation_class: Map.fetch!(attrs, :operation_class),
      capability_set: capabilities,
      cost_profile_ref: Map.fetch!(attrs, :cost_profile_ref),
      context_window_ref: Map.fetch!(attrs, :context_window_ref),
      retention_posture_ref: Map.fetch!(attrs, :retention_posture_ref),
      materialization_posture: Map.fetch!(attrs, :materialization_posture),
      raw_material_present?: false
    }
  end

  defp materialization_ref(attrs, capabilities) do
    profile_ref =
      attrs
      |> Map.fetch!(:model_profile_ref)
      |> String.replace_prefix("model-profile://", "")

    capability =
      capabilities
      |> List.first()
      |> Atom.to_string()

    "model-materialization://" <> Enum.join([profile_ref, capability], "/")
  end

  defp present?(nil), do: false
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(value) when is_atom(value), do: true
  defp present?(value), do: not is_nil(value)
end
