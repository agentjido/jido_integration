defmodule Jido.Integration.Trigger.Descriptor do
  @moduledoc """
  Trigger descriptor — declares an inbound event source in a connector manifest.

  Triggers represent webhook endpoints, polling sources, or streaming
  connections that push events into the integration platform.

  ## Fields

  - `id` — unique trigger identifier
  - `class` — trigger class (webhook, polling, schedule, stream)
  - `summary` — human-readable description
  - `payload_schema` — JSON schema for the trigger payload
  - `delivery_semantics` — at_least_once | exactly_once
  - `verification` — signature verification config
  - `callback_topology` — dynamic_per_install | static_per_app
  - `tenant_resolution_keys` — ordered selectors for tenant disambiguation
  - `replay_window_days` — dedupe window (default 7)
  """

  alias Jido.Integration.Error

  @valid_classes ~w(webhook polling schedule stream)
  @valid_delivery ~w(at_least_once exactly_once)
  @valid_topologies ~w(dynamic_per_install static_per_app)

  @type t :: %__MODULE__{
          id: String.t(),
          class: String.t(),
          summary: String.t(),
          payload_schema: map(),
          delivery_semantics: String.t(),
          ordering_scope: String.t(),
          checkpoint_mode: String.t(),
          dedupe_key_path: String.t() | nil,
          max_delivery_lag_s: non_neg_integer(),
          verification: map() | nil,
          callback_topology: String.t(),
          tenant_resolution_keys: [String.t()],
          replay_window_days: non_neg_integer(),
          backfill_supported: boolean()
        }

  @enforce_keys [:id, :class, :summary]
  defstruct [
    :id,
    :class,
    :summary,
    :dedupe_key_path,
    :verification,
    payload_schema: %{"type" => "object"},
    delivery_semantics: "at_least_once",
    ordering_scope: "tenant_connector",
    checkpoint_mode: "cursor",
    max_delivery_lag_s: 300,
    callback_topology: "dynamic_per_install",
    tenant_resolution_keys: [],
    replay_window_days: 7,
    backfill_supported: false
  ]

  @doc """
  Create a new trigger descriptor from a map.
  """
  @spec new(map()) :: {:ok, t()} | {:error, Error.t()}
  def new(attrs) when is_map(attrs) do
    with :ok <- validate_required(attrs),
         :ok <- validate_class(attrs) do
      descriptor = %__MODULE__{
        id: Map.fetch!(attrs, "id"),
        class: Map.fetch!(attrs, "class"),
        summary: Map.fetch!(attrs, "summary"),
        payload_schema: Map.get(attrs, "payload_schema", %{"type" => "object"}),
        delivery_semantics: Map.get(attrs, "delivery_semantics", "at_least_once"),
        ordering_scope: Map.get(attrs, "ordering_scope", "tenant_connector"),
        checkpoint_mode: Map.get(attrs, "checkpoint_mode", "cursor"),
        dedupe_key_path: Map.get(attrs, "dedupe_key_path"),
        max_delivery_lag_s: Map.get(attrs, "max_delivery_lag_s", 300),
        verification: Map.get(attrs, "verification"),
        callback_topology: Map.get(attrs, "callback_topology", "dynamic_per_install"),
        tenant_resolution_keys: Map.get(attrs, "tenant_resolution_keys", []),
        replay_window_days: Map.get(attrs, "replay_window_days", 7),
        backfill_supported: Map.get(attrs, "backfill_supported", false)
      }

      {:ok, descriptor}
    end
  end

  @doc "Serialize to a JSON-encodable map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = d) do
    %{
      "id" => d.id,
      "class" => d.class,
      "summary" => d.summary,
      "payload_schema" => d.payload_schema,
      "delivery_semantics" => d.delivery_semantics,
      "ordering_scope" => d.ordering_scope,
      "checkpoint_mode" => d.checkpoint_mode,
      "dedupe_key_path" => d.dedupe_key_path,
      "max_delivery_lag_s" => d.max_delivery_lag_s,
      "verification" => d.verification,
      "callback_topology" => d.callback_topology,
      "tenant_resolution_keys" => d.tenant_resolution_keys,
      "replay_window_days" => d.replay_window_days,
      "backfill_supported" => d.backfill_supported
    }
  end

  @doc "Valid trigger classes."
  @spec valid_classes() :: [String.t()]
  def valid_classes, do: @valid_classes

  @doc "Valid delivery semantics."
  @spec valid_delivery_semantics() :: [String.t()]
  def valid_delivery_semantics, do: @valid_delivery

  @doc "Valid callback topologies."
  @spec valid_topologies() :: [String.t()]
  def valid_topologies, do: @valid_topologies

  defp validate_required(attrs) do
    required = ~w(id class summary)
    missing = Enum.filter(required, &(not Map.has_key?(attrs, &1)))

    if missing == [] do
      :ok
    else
      {:error,
       Error.new(:invalid_request, "Trigger descriptor missing: #{Enum.join(missing, ", ")}")}
    end
  end

  defp validate_class(attrs) do
    class = Map.get(attrs, "class")

    if class in @valid_classes do
      :ok
    else
      {:error, Error.new(:invalid_request, "Invalid trigger class: #{inspect(class)}")}
    end
  end
end
