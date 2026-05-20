defmodule Jido.Integration.Lanes.LowerEffectReceipt do
  @moduledoc """
  Mezzanine-facing lower receipt for a governed effect.
  """

  alias Jido.Integration.V2.Contracts

  @contract_name "JidoIntegration.LowerEffectReceipt.v1"
  @statuses %{
    "success" => :success,
    "failure" => :failure,
    "partial" => :partial,
    "timeout" => :timeout,
    "compensated" => :compensated,
    "denied" => :denied,
    "cancelled" => :cancelled
  }
  @raw_secret_keys MapSet.new([
                     "api_key",
                     "access_token",
                     "refresh_token",
                     "secret",
                     "token",
                     "password",
                     "private_key",
                     "auth_header",
                     "authorization",
                     "cookie",
                     "session_cookie",
                     "raw_credential",
                     "credential_payload"
                   ])
  @fields [
    :contract_name,
    :receipt_ref,
    :effect_ref,
    :status,
    :lower_receipt_ref,
    :lower_facts,
    :projection_updates,
    :evidence_refs,
    :trace_ref,
    :completed_at,
    :extensions
  ]
  @required [
    :receipt_ref,
    :effect_ref,
    :status,
    :lower_receipt_ref,
    :lower_facts,
    :evidence_refs,
    :trace_ref,
    :completed_at
  ]

  @enforce_keys @required
  defstruct @fields

  @type status ::
          :success | :failure | :partial | :timeout | :compensated | :denied | :cancelled

  @type t :: %__MODULE__{
          contract_name: String.t(),
          receipt_ref: String.t(),
          effect_ref: String.t(),
          status: status(),
          lower_receipt_ref: String.t(),
          lower_facts: map(),
          projection_updates: [map()],
          evidence_refs: [String.t()],
          trace_ref: String.t(),
          completed_at: DateTime.t(),
          extensions: map()
        }

  @spec contract_name() :: String.t()
  def contract_name, do: @contract_name

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = receipt), do: normalize(receipt)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs
    |> build()
    |> normalize()
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, receipt} -> receipt
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = receipt) do
    %{
      "contract_name" => @contract_name,
      "receipt_ref" => receipt.receipt_ref,
      "effect_ref" => receipt.effect_ref,
      "status" => Atom.to_string(receipt.status),
      "lower_receipt_ref" => receipt.lower_receipt_ref,
      "lower_facts" => serialize(receipt.lower_facts),
      "projection_updates" => serialize(receipt.projection_updates),
      "evidence_refs" => receipt.evidence_refs,
      "trace_ref" => receipt.trace_ref,
      "completed_at" => DateTime.to_iso8601(receipt.completed_at),
      "extensions" => serialize(receipt.extensions)
    }
  end

  defp build(attrs) do
    attrs = Map.new(attrs)

    struct!(
      __MODULE__,
      for field <- @fields, into: %{} do
        {field, field_value(attrs, field)}
      end
    )
  end

  defp normalize(%__MODULE__{} = receipt) do
    normalized = %__MODULE__{
      receipt
      | contract_name: @contract_name,
        receipt_ref: required_string(receipt.receipt_ref, :receipt_ref),
        effect_ref: required_string(receipt.effect_ref, :effect_ref),
        status: normalize_status!(receipt.status),
        lower_receipt_ref: required_string(receipt.lower_receipt_ref, :lower_receipt_ref),
        lower_facts: map!(receipt.lower_facts || %{}, :lower_facts),
        projection_updates: map_list!(receipt.projection_updates || [], :projection_updates),
        evidence_refs: string_list!(receipt.evidence_refs || [], :evidence_refs),
        trace_ref: required_string(receipt.trace_ref, :trace_ref),
        completed_at: completed_at!(receipt.completed_at),
        extensions: map!(receipt.extensions || %{}, :extensions)
    }

    reject_raw_secret_material!(normalized)
    {:ok, normalized}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp reject_raw_secret_material!(%__MODULE__{} = receipt) do
    inspected = %{
      "lower_facts" => receipt.lower_facts,
      "projection_updates" => receipt.projection_updates,
      "extensions" => receipt.extensions
    }

    case raw_secret_path(inspected, []) do
      nil ->
        :ok

      path ->
        raise ArgumentError,
              "lower effect receipt must not contain raw credential material at #{Enum.join(path, ".")}"
    end
  end

  defp normalize_status!(status) when is_atom(status) do
    if Atom.to_string(status) in Map.keys(@statuses) do
      status
    else
      raise ArgumentError, "unsupported lower effect receipt status: #{inspect(status)}"
    end
  end

  defp normalize_status!(status) when is_binary(status) do
    case Map.fetch(@statuses, status) do
      {:ok, normalized} -> normalized
      :error -> raise ArgumentError, "unsupported lower effect receipt status: #{inspect(status)}"
    end
  end

  defp normalize_status!(status) do
    raise ArgumentError, "unsupported lower effect receipt status: #{inspect(status)}"
  end

  defp completed_at!(%DateTime{} = completed_at), do: completed_at

  defp completed_at!(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, completed_at, _offset} ->
        completed_at

      {:error, reason} ->
        raise ArgumentError, "completed_at must be ISO8601, got: #{inspect(reason)}"
    end
  end

  defp completed_at!(value) do
    raise ArgumentError,
          "completed_at must be a DateTime or ISO8601 string, got: #{inspect(value)}"
  end

  defp field_value(attrs, field), do: Map.get(attrs, field, Map.get(attrs, Atom.to_string(field)))

  defp required_string(value, field) do
    value
    |> Contracts.validate_non_empty_string!(Atom.to_string(field))
    |> String.trim()
  end

  defp map!(value, _field) when is_map(value), do: Map.new(value)

  defp map!(value, field) do
    raise ArgumentError, "#{field} must be a map, got: #{inspect(value)}"
  end

  defp map_list!(values, _field) when is_list(values) do
    Enum.map(values, fn
      value when is_map(value) ->
        Map.new(value)

      value ->
        raise ArgumentError, "projection_updates entries must be maps, got: #{inspect(value)}"
    end)
  end

  defp map_list!(values, field) do
    raise ArgumentError, "#{field} must be a list of maps, got: #{inspect(values)}"
  end

  defp string_list!(values, field) when is_list(values) do
    Enum.map(values, &required_string(&1, field))
  end

  defp string_list!(values, field) do
    raise ArgumentError, "#{field} must be a list of strings, got: #{inspect(values)}"
  end

  defp raw_secret_path(%{} = map, path) do
    Enum.find_value(map, fn {key, value} ->
      segment = to_string(key)
      next_path = path ++ [segment]

      cond do
        MapSet.member?(@raw_secret_keys, String.downcase(segment)) -> next_path
        is_map(value) or is_list(value) -> raw_secret_path(value, next_path)
        true -> nil
      end
    end)
  end

  defp raw_secret_path(values, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.find_value(fn {value, index} ->
      if is_map(value) or is_list(value) do
        raw_secret_path(value, path ++ [Integer.to_string(index)])
      end
    end)
  end

  defp raw_secret_path(_value, _path), do: nil

  defp serialize(value) when is_atom(value), do: Atom.to_string(value)
  defp serialize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp serialize(values) when is_list(values), do: Enum.map(values, &serialize/1)

  defp serialize(%{} = map) do
    Map.new(map, fn {key, value} -> {to_string(key), serialize(value)} end)
  end

  defp serialize(value), do: value
end
