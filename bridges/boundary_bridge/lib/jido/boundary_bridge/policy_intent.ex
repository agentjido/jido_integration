defmodule Jido.BoundaryBridge.PolicyIntent do
  @moduledoc """
  Lossy execution-time policy intent projection.

  This shape is intentionally smaller than authoritative policy contracts such
  as `Gateway.sandbox`.
  """

  alias Jido.BoundaryBridge.Contracts
  alias Jido.BoundaryBridge.Schema

  @schema Zoi.struct(
            __MODULE__,
            %{
              sandbox_level:
                Contracts.enumish_schema(
                  [:strict, :standard, :none],
                  "policy_intent.sandbox_level"
                )
                |> Zoi.default(:standard),
              egress:
                Contracts.enumish_schema([:blocked, :restricted, :open], "policy_intent.egress")
                |> Zoi.default(:restricted),
              approvals:
                Contracts.enumish_schema([:none, :manual, :auto], "policy_intent.approvals")
                |> Zoi.default(:auto),
              allowed_tools:
                Contracts.string_list_schema("policy_intent.allowed_tools")
                |> Zoi.default([]),
              file_scope:
                Contracts.non_empty_string_schema("policy_intent.file_scope")
                |> Zoi.nullish()
                |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t() | nil) :: {:ok, t()} | {:error, Exception.t()}
  def new(nil), do: {:ok, Schema.new!(__MODULE__, @schema, %{})}
  def new(%__MODULE__{} = policy_intent), do: {:ok, policy_intent}

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    attrs
    |> Map.new()
    |> prepare_attrs()
    |> then(&Schema.new(__MODULE__, @schema, &1))
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t() | nil) :: t()
  def new!(nil), do: Schema.new!(__MODULE__, @schema, %{})
  def new!(%__MODULE__{} = policy_intent), do: policy_intent

  def new!(attrs) do
    case new(attrs) do
      {:ok, policy_intent} -> policy_intent
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = policy_intent), do: Map.from_struct(policy_intent)

  defp prepare_attrs(attrs) do
    %{
      sandbox_level:
        Contracts.get(attrs, :sandbox_level, Contracts.get(attrs, :level, :standard)),
      egress: Contracts.get(attrs, :egress, :restricted),
      approvals: Contracts.get(attrs, :approvals, :auto),
      allowed_tools: Contracts.get(attrs, :allowed_tools, []),
      file_scope: Contracts.get(attrs, :file_scope)
    }
  end
end
