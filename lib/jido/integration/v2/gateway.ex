defmodule Jido.Integration.V2.Gateway do
  @moduledoc """
  Canonical gateway input for pre-dispatch admission and in-run execution policy.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Schema

  @default_sandbox %{
    level: :standard,
    egress: :restricted,
    approvals: :auto,
    file_scope: nil,
    allowed_tools: []
  }

  @sandbox_levels [:strict, :standard, :none]
  @approvals [:none, :manual, :auto]
  @egress_policies [:blocked, :restricted, :open]

  @sandbox_schema Contracts.strict_object!(
                    level:
                      Contracts.enumish_schema(@sandbox_levels, "gateway.sandbox.level")
                      |> Zoi.default(:standard),
                    egress:
                      Contracts.enumish_schema(@egress_policies, "gateway.sandbox.egress")
                      |> Zoi.default(:restricted),
                    approvals:
                      Contracts.enumish_schema(@approvals, "gateway.sandbox.approvals")
                      |> Zoi.default(:auto),
                    file_scope:
                      Contracts.non_empty_string_schema("gateway.sandbox.file_scope")
                      |> Zoi.nullish()
                      |> Zoi.optional(),
                    allowed_tools:
                      Contracts.string_list_schema("gateway.sandbox.allowed_tools")
                      |> Zoi.default([])
                  )

  @schema Zoi.struct(
            __MODULE__,
            %{
              actor_id:
                Contracts.non_empty_string_schema("gateway.actor_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              tenant_id:
                Contracts.non_empty_string_schema("gateway.tenant_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              environment:
                Zoi.union([Zoi.atom(), Zoi.string()]) |> Zoi.nullish() |> Zoi.optional(),
              trace_id:
                Contracts.non_empty_string_schema("gateway.trace_id")
                |> Zoi.nullish()
                |> Zoi.optional(),
              credential_ref:
                Contracts.struct_schema(CredentialRef, "gateway.credential_ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              runtime_class:
                Contracts.enumish_schema([:direct, :session, :stream], "gateway.runtime_class"),
              allowed_operations:
                Contracts.string_list_schema("gateway.allowed_operations") |> Zoi.default([]),
              sandbox: @sandbox_schema |> Zoi.default(@default_sandbox),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type sandbox_t :: %{
          level: Contracts.sandbox_level(),
          egress: Contracts.egress_policy(),
          approvals: Contracts.approvals(),
          file_scope: String.t() | nil,
          allowed_tools: [String.t()]
        }
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = gateway), do: normalize(gateway)

  def new(attrs) do
    case Schema.new(__MODULE__, @schema, attrs) do
      {:ok, gateway} -> normalize(gateway)
      {:error, %ArgumentError{} = error} -> {:error, error}
    end
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = gateway), do: normalize(gateway) |> then(fn {:ok, value} -> value end)

  def new!(attrs) do
    case new(attrs) do
      {:ok, gateway} -> gateway
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  defp normalize(%__MODULE__{} = gateway) do
    {:ok,
     %__MODULE__{
       gateway
       | environment: normalize_environment(gateway.environment),
         sandbox: normalize_sandbox(gateway.sandbox)
     }}
  end

  defp normalize_environment(nil), do: nil
  defp normalize_environment(value) when is_atom(value), do: value

  defp normalize_environment(value) when is_binary(value),
    do: Contracts.validate_non_empty_string!(value, "environment")

  defp normalize_sandbox(sandbox) when is_map(sandbox) do
    %{
      level: Contracts.validate_sandbox_level!(Contracts.get(sandbox, :level, :standard)),
      egress: Contracts.validate_egress_policy!(Contracts.get(sandbox, :egress, :restricted)),
      approvals: Contracts.validate_approvals!(Contracts.get(sandbox, :approvals, :auto)),
      file_scope: normalize_file_scope(Contracts.get(sandbox, :file_scope)),
      allowed_tools:
        Contracts.normalize_string_list!(
          Contracts.get(sandbox, :allowed_tools, []),
          "sandbox.allowed_tools"
        )
    }
  end

  defp normalize_file_scope(nil), do: nil

  defp normalize_file_scope(file_scope),
    do: Contracts.validate_non_empty_string!(file_scope, "sandbox.file_scope")
end
