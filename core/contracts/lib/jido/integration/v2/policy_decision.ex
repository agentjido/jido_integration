defmodule Jido.Integration.V2.PolicyDecision do
  @moduledoc """
  Captures the control-plane admission decision for a run.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @statuses [:allowed, :denied, :shed]

  @schema Zoi.struct(
            __MODULE__,
            %{
              status: Contracts.enumish_schema(@statuses, "policy_decision.status"),
              reasons: Contracts.string_list_schema("policy_decision.reasons") |> Zoi.default([]),
              execution_policy: Contracts.any_map_schema(),
              audit_context: Contracts.any_map_schema()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = policy_decision), do: {:ok, policy_decision}
  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = policy_decision), do: policy_decision
  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)

  @spec allow(map(), map()) :: t()
  def allow(execution_policy, audit_context)
      when is_map(execution_policy) and is_map(audit_context) do
    new!(%{
      status: :allowed,
      reasons: [],
      execution_policy: execution_policy,
      audit_context: audit_context
    })
  end

  @spec deny([String.t()], map(), map()) :: t()
  def deny(reasons, execution_policy, audit_context)
      when is_list(reasons) and is_map(execution_policy) and is_map(audit_context) do
    new!(%{
      status: :denied,
      reasons: reasons,
      execution_policy: execution_policy,
      audit_context: audit_context
    })
  end

  @spec shed([String.t()], map(), map()) :: t()
  def shed(reasons, execution_policy, audit_context)
      when is_list(reasons) and is_map(execution_policy) and is_map(audit_context) do
    new!(%{
      status: :shed,
      reasons: reasons,
      execution_policy: execution_policy,
      audit_context: audit_context
    })
  end
end
