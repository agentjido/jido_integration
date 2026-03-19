defmodule Jido.Integration.V2.Gateway.Policy do
  @moduledoc """
  Normalized capability policy contract for gateway admission and execution.
  """

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @schema Zoi.struct(
            __MODULE__,
            %{
              actor: Contracts.any_map_schema(),
              tenant: Contracts.any_map_schema(),
              environment: Contracts.any_map_schema(),
              capability: Contracts.any_map_schema(),
              runtime: Contracts.any_map_schema(),
              sandbox: Contracts.any_map_schema()
            },
            coerce: true
          )

  @type actor_t :: %{required: boolean(), allowed_ids: [String.t()]}
  @type tenant_t :: %{required: boolean(), allowed_ids: [String.t()]}
  @type environment_t :: %{allowed: [String.t()]}
  @type capability_t :: %{allowed_operations: [String.t()], required_scopes: [String.t()]}
  @type runtime_t :: %{allowed: [Contracts.runtime_class()]}
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
  def new(%__MODULE__{} = policy), do: {:ok, policy}
  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = policy), do: policy
  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)

  @spec from_capability(Capability.t()) :: t()
  def from_capability(%Capability{} = capability) do
    policy = Contracts.get(capability.metadata, :policy, %{})
    actor = Contracts.get(policy, :actor, %{})
    tenant = Contracts.get(policy, :tenant, %{})
    environment = Contracts.get(policy, :environment, %{})
    capability_policy = Contracts.get(policy, :capability, %{})
    runtime = Contracts.get(policy, :runtime, %{})
    sandbox = Contracts.get(policy, :sandbox, %{})

    new!(%{
      actor: %{
        required: Contracts.get(actor, :required, true),
        allowed_ids:
          normalize_string_list(
            policy,
            actor,
            :allowed_actor_ids,
            :allowed_ids,
            "actor.allowed_ids"
          )
      },
      tenant: %{
        required: Contracts.get(tenant, :required, true),
        allowed_ids:
          normalize_string_list(
            policy,
            tenant,
            :allowed_tenant_ids,
            :allowed_ids,
            "tenant.allowed_ids"
          )
      },
      environment: %{
        allowed:
          normalize_environment_list(
            Contracts.get(environment, :allowed, Contracts.get(policy, :allowed_environments, []))
          )
      },
      capability: %{
        allowed_operations:
          normalize_string_list(
            policy,
            capability_policy,
            :allowed_operations,
            :allowed_operations,
            "capability.allowed_operations",
            [capability.id]
          ),
        required_scopes: Capability.required_scopes(capability)
      },
      runtime: %{
        allowed:
          normalize_runtime_classes(
            Contracts.get(
              runtime,
              :allowed,
              Contracts.get(policy, :allowed_runtime_classes, [capability.runtime_class])
            )
          )
      },
      sandbox: %{
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
    })
  end

  defp normalize_string_list(root, nested, root_key, nested_key, field_name, default \\ []) do
    value = Contracts.get(nested, nested_key, Contracts.get(root, root_key, default))
    Contracts.normalize_string_list!(value, field_name)
  end

  defp normalize_environment_list(values) when is_list(values) do
    Enum.map(values, fn value ->
      value
      |> normalize_environment()
      |> to_string()
    end)
  end

  defp normalize_environment_list(values) do
    raise ArgumentError, "allowed environments must be a list, got: #{inspect(values)}"
  end

  defp normalize_environment(value) when is_atom(value), do: value

  defp normalize_environment(value) when is_binary(value),
    do: Contracts.validate_non_empty_string!(value, "environment")

  defp normalize_environment(value) do
    raise ArgumentError, "environment must be an atom or string, got: #{inspect(value)}"
  end

  defp normalize_runtime_classes(values) when is_list(values) do
    Enum.map(values, &Contracts.validate_runtime_class!/1)
  end

  defp normalize_runtime_classes(values) do
    raise ArgumentError, "allowed runtime classes must be a list, got: #{inspect(values)}"
  end

  defp normalize_file_scope(nil), do: nil

  defp normalize_file_scope(file_scope),
    do: Contracts.validate_non_empty_string!(file_scope, "sandbox.file_scope")
end
