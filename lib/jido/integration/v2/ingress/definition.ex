defmodule Jido.Integration.V2.Ingress.Definition do
  @moduledoc """
  Ingress-side trigger definition used to normalize webhook and polling inputs.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.TriggerSpec

  @enforce_keys [
    :source,
    :connector_id,
    :trigger_id,
    :capability_id,
    :signal_type,
    :signal_source
  ]
  defstruct [
    :source,
    :connector_id,
    :trigger_id,
    :capability_id,
    :signal_type,
    :signal_source,
    :validator,
    :verification,
    dedupe_ttl_seconds: 86_400
  ]

  @type validator :: (map() -> :ok | {:error, term()})

  @type t :: %__MODULE__{
          source: Contracts.trigger_source(),
          connector_id: String.t(),
          trigger_id: String.t(),
          capability_id: String.t(),
          signal_type: String.t(),
          signal_source: String.t(),
          validator: validator() | nil,
          verification: map() | nil,
          dedupe_ttl_seconds: pos_integer()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)

    struct!(__MODULE__, %{
      source: Contracts.validate_trigger_source!(Map.fetch!(attrs, :source)),
      connector_id:
        Contracts.validate_non_empty_string!(Map.fetch!(attrs, :connector_id), "connector_id"),
      trigger_id:
        Contracts.validate_non_empty_string!(Map.fetch!(attrs, :trigger_id), "trigger_id"),
      capability_id:
        Contracts.validate_non_empty_string!(Map.fetch!(attrs, :capability_id), "capability_id"),
      signal_type:
        Contracts.validate_non_empty_string!(Map.fetch!(attrs, :signal_type), "signal_type"),
      signal_source:
        Contracts.validate_non_empty_string!(Map.fetch!(attrs, :signal_source), "signal_source"),
      validator: normalize_validator(Map.get(attrs, :validator)),
      verification: normalize_verification(Map.get(attrs, :verification)),
      dedupe_ttl_seconds: normalize_ttl(Map.get(attrs, :dedupe_ttl_seconds, 86_400))
    })
  end

  @spec from_trigger!(String.t(), TriggerSpec.t(), map() | keyword()) :: t()
  def from_trigger!(connector_id, %TriggerSpec{} = trigger_spec, attrs \\ %{}) do
    attrs = if is_list(attrs), do: Map.new(attrs), else: Map.new(attrs)

    new!(%{
      source: trigger_spec.delivery_mode,
      connector_id: connector_id,
      trigger_id: Map.get(attrs, :trigger_id, trigger_spec.trigger_id),
      capability_id: trigger_spec.trigger_id,
      signal_type: Map.get(attrs, :signal_type) || TriggerSpec.sensor_signal_type(trigger_spec),
      signal_source:
        Map.get(attrs, :signal_source) || TriggerSpec.sensor_signal_source(trigger_spec),
      validator: Map.get(attrs, :validator, schema_validator(trigger_spec.signal_schema)),
      verification: Map.get(attrs, :verification),
      dedupe_ttl_seconds: Map.get(attrs, :dedupe_ttl_seconds, 86_400)
    })
  end

  defp schema_validator(signal_schema) do
    fn payload ->
      case Zoi.parse(signal_schema, payload) do
        {:ok, _validated_payload} -> :ok
        {:error, errors} -> {:error, {:schema_invalid, errors}}
      end
    end
  end

  defp normalize_validator(nil), do: nil
  defp normalize_validator(validator) when is_function(validator, 1), do: validator

  defp normalize_validator(validator) do
    raise ArgumentError, "validator must be a unary function or nil, got: #{inspect(validator)}"
  end

  defp normalize_verification(nil), do: nil

  defp normalize_verification(verification) when is_map(verification) do
    %{
      algorithm: Map.get(verification, :algorithm, :sha256),
      secret: Contracts.fetch!(verification, :secret),
      signature_header:
        Contracts.validate_non_empty_string!(
          Contracts.fetch!(verification, :signature_header),
          "verification.signature_header"
        )
    }
  end

  defp normalize_verification(verification) do
    raise ArgumentError,
          "verification must be a map or nil, got: #{inspect(verification)}"
  end

  defp normalize_ttl(ttl_seconds) when is_integer(ttl_seconds) and ttl_seconds > 0,
    do: ttl_seconds

  defp normalize_ttl(ttl_seconds) do
    raise ArgumentError,
          "dedupe_ttl_seconds must be a positive integer, got: #{inspect(ttl_seconds)}"
  end
end
