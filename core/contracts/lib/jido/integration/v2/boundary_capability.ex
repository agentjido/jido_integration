defmodule Jido.Integration.V2.BoundaryCapability do
  @moduledoc """
  Typed boundary capability advertisement for target descriptors.

  `TargetDescriptor.extensions["boundary"]` is the authored baseline contract
  for boundary capability advertisement. Runtimes may merge worker-local facts
  into that baseline at execution time to build a runtime-merged live
  capability view, but those live facts must sharpen the authored baseline
  rather than silently widen it.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @schema Zoi.struct(
            __MODULE__,
            %{
              supported: Zoi.boolean() |> Zoi.default(false),
              boundary_classes:
                Contracts.string_list_schema("boundary_capability.boundary_classes")
                |> Zoi.default([]),
              attach_modes:
                Contracts.string_list_schema("boundary_capability.attach_modes")
                |> Zoi.default([]),
              checkpointing: Zoi.boolean() |> Zoi.default(false)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for boundary capability advertisements."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds a boundary capability advertisement from validated attributes."
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = capability), do: {:ok, capability}

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    case Schema.new(__MODULE__, @schema, attrs) do
      {:ok, capability} -> {:ok, capability}
      {:error, %ArgumentError{} = error} -> {:error, error}
    end
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @doc "Builds a boundary capability advertisement or raises on validation failure."
  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = capability), do: capability

  def new!(attrs) do
    case new(attrs) do
      {:ok, capability} -> capability
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @doc """
  Merges worker-local facts into an authored baseline advertisement.

  Merge semantics are intentionally restrictive:

  - boolean support and checkpointing flags may tighten from `true` to `false`
  - boundary class and attach mode lists may narrow through intersection
  - live facts do not widen the authored baseline silently
  """
  @spec merge(t() | map() | keyword() | nil, t() | map() | keyword() | nil) :: t() | nil
  def merge(nil, nil), do: nil
  def merge(authored, nil), do: authored |> new!()
  def merge(nil, live_facts), do: live_facts |> new!()

  def merge(authored, live_facts) do
    authored = new!(authored)
    live_facts = normalize_live_facts!(live_facts)

    new!(%{
      supported:
        authored.supported and
          fetch_optional_boolean!(live_facts, :supported, authored.supported, "supported"),
      boundary_classes:
        sharpen_list(
          authored.boundary_classes,
          fetch_optional_string_list!(live_facts, :boundary_classes, "boundary_classes")
        ),
      attach_modes:
        sharpen_list(
          authored.attach_modes,
          fetch_optional_string_list!(live_facts, :attach_modes, "attach_modes")
        ),
      checkpointing:
        authored.checkpointing and
          fetch_optional_boolean!(
            live_facts,
            :checkpointing,
            authored.checkpointing,
            "checkpointing"
          )
    })
  end

  defp normalize_live_facts!(%__MODULE__{} = live_facts), do: Map.from_struct(live_facts)
  defp normalize_live_facts!(live_facts) when is_map(live_facts), do: live_facts
  defp normalize_live_facts!(live_facts) when is_list(live_facts), do: Map.new(live_facts)

  defp normalize_live_facts!(live_facts) do
    raise ArgumentError,
          "live boundary facts must be a map or keyword list, got: #{inspect(live_facts)}"
  end

  defp fetch_optional_boolean!(map, key, default, field_name) when is_map(map) do
    case fetch_optional(map, key) do
      {:ok, value} when is_boolean(value) ->
        value

      {:ok, value} ->
        raise ArgumentError, "#{field_name} must be a boolean, got: #{inspect(value)}"

      :error ->
        default
    end
  end

  defp fetch_optional_string_list!(map, key, field_name) when is_map(map) do
    case fetch_optional(map, key) do
      {:ok, value} -> Contracts.normalize_string_list!(value, field_name)
      :error -> nil
    end
  end

  defp fetch_optional(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        Map.fetch(map, Atom.to_string(key))
    end
  end

  defp sharpen_list(authored, nil), do: authored
  defp sharpen_list(authored, live_facts), do: Enum.filter(authored, &(&1 in live_facts))
end
