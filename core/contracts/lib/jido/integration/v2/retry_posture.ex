defmodule Jido.Integration.V2.RetryPosture do
  @moduledoc """
  Consumer mirror for the Phase 4 platform retry posture contract.

  Contract: `Platform.RetryPosture.v1`.
  """

  @contract_name "Platform.RetryPosture.v1"
  @contract_version "1.0.0"
  @retry_classes [
    :never,
    :safe_idempotent,
    :after_input_change,
    :after_redecision,
    :manual_operator
  ]

  @required_binary_fields [
    :tenant_ref,
    :installation_ref,
    :workspace_ref,
    :project_ref,
    :environment_ref,
    :resource_ref,
    :authority_packet_ref,
    :permission_decision_ref,
    :idempotency_key,
    :trace_id,
    :correlation_id,
    :release_manifest_ref,
    :operation_ref,
    :owner_repo,
    :producer_ref,
    :consumer_ref,
    :failure_class,
    :idempotency_scope,
    :dead_letter_ref,
    :safe_action_code
  ]
  @optional_binary_fields [:principal_ref, :system_actor_ref, :operator_message_ref]

  defstruct [
    :contract_name,
    :contract_version,
    :tenant_ref,
    :installation_ref,
    :workspace_ref,
    :project_ref,
    :environment_ref,
    :principal_ref,
    :system_actor_ref,
    :resource_ref,
    :authority_packet_ref,
    :permission_decision_ref,
    :idempotency_key,
    :trace_id,
    :correlation_id,
    :release_manifest_ref,
    :operation_ref,
    :owner_repo,
    :producer_ref,
    :consumer_ref,
    :retry_class,
    :failure_class,
    :max_attempts,
    :backoff_policy,
    :idempotency_scope,
    :dead_letter_ref,
    :safe_action_code,
    :retry_after_ms,
    :operator_message_ref
  ]

  @type t :: %__MODULE__{}

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec contract_version() :: String.t()
  def contract_version, do: @contract_version

  @spec retry_classes() :: [atom()]
  def retry_classes, do: @retry_classes

  @spec new(map() | keyword()) ::
          {:ok, t()}
          | {:error, {:missing_required_fields, [atom()]}}
          | {:error, :invalid_retry_posture}
  def new(attrs) do
    with {:ok, attrs} <- normalize_attrs(attrs),
         [] <- missing_required_fields(attrs),
         true <- optional_binary_fields?(attrs),
         true <- non_neg_integer?(Map.get(attrs, :max_attempts)),
         true <- non_empty_map?(Map.get(attrs, :backoff_policy)),
         true <- optional_non_neg_integer?(Map.get(attrs, :retry_after_ms)),
         {:ok, retry_class} <- enum_atom(Map.get(attrs, :retry_class), @retry_classes),
         :ok <- validate_retry_semantics(attrs, retry_class) do
      {:ok, build(attrs, retry_class)}
    else
      fields when is_list(fields) -> {:error, {:missing_required_fields, fields}}
      _error -> {:error, :invalid_retry_posture}
    end
  end

  defp build(attrs, retry_class) do
    struct!(
      __MODULE__,
      Map.merge(attrs, %{
        contract_name: @contract_name,
        contract_version: @contract_version,
        retry_class: retry_class
      })
    )
  end

  defp validate_retry_semantics(attrs, :never) do
    if Map.fetch!(attrs, :max_attempts) == 0, do: :ok, else: :error
  end

  defp validate_retry_semantics(attrs, _retry_class) do
    if Map.fetch!(attrs, :max_attempts) > 0, do: :ok, else: :error
  end

  defp missing_required_fields(attrs) do
    binary_missing =
      @required_binary_fields
      |> Enum.reject(fn field -> present_binary?(Map.get(attrs, field)) end)

    actor_missing =
      if present_binary?(Map.get(attrs, :principal_ref)) or
           present_binary?(Map.get(attrs, :system_actor_ref)) do
        []
      else
        [:principal_ref_or_system_actor_ref]
      end

    integer_missing =
      if Map.has_key?(attrs, :max_attempts), do: [], else: [:max_attempts]

    map_missing =
      if non_empty_map?(Map.get(attrs, :backoff_policy)), do: [], else: [:backoff_policy]

    binary_missing ++ actor_missing ++ integer_missing ++ map_missing
  end

  defp normalize_attrs(attrs) when is_list(attrs), do: {:ok, Map.new(attrs)}

  defp normalize_attrs(attrs) when is_map(attrs) do
    if Map.has_key?(attrs, :__struct__) do
      {:ok, Map.from_struct(attrs)}
    else
      {:ok, attrs}
    end
  end

  defp normalize_attrs(_attrs), do: {:error, :invalid_attrs}

  defp optional_binary_fields?(attrs) do
    Enum.all?(@optional_binary_fields, fn field ->
      value = Map.get(attrs, field)
      is_nil(value) or present_binary?(value)
    end)
  end

  defp enum_atom(value, allowed) when is_atom(value) do
    if value in allowed, do: {:ok, value}, else: :error
  end

  defp enum_atom(value, allowed) when is_binary(value) do
    allowed
    |> Enum.find(&(Atom.to_string(&1) == value))
    |> case do
      nil -> :error
      atom -> {:ok, atom}
    end
  end

  defp enum_atom(_value, _allowed), do: :error

  defp present_binary?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0
  defp non_neg_integer?(value), do: is_integer(value) and value >= 0
  defp optional_non_neg_integer?(nil), do: true
  defp optional_non_neg_integer?(value), do: non_neg_integer?(value)
  defp non_empty_map?(value), do: is_map(value) and map_size(value) > 0
end
