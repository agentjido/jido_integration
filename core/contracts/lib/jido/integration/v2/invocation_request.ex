defmodule Jido.Integration.V2.InvocationRequest do
  @moduledoc """
  Typed public request for capability invocation through the v2 facade.

  The request keeps the stable control-plane invoke fields explicit while still
  allowing non-reserved extension opts to flow through to runtime context.

  When a capability requires auth, the public binding is `connection_id`.
  Credential refs remain internal auth and execution plumbing.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Gateway

  @reserved_extension_keys [
    :connection_id,
    :actor_id,
    :tenant_id,
    :environment,
    :trace_id,
    :allowed_operations,
    :sandbox,
    :target_id,
    :aggregator_id,
    :aggregator_epoch
  ]

  @enforce_keys [:capability_id]
  defstruct [
    :capability_id,
    :connection_id,
    :actor_id,
    :tenant_id,
    :environment,
    :trace_id,
    :target_id,
    :aggregator_id,
    :aggregator_epoch,
    input: %{},
    allowed_operations: [],
    sandbox: %{
      level: :standard,
      egress: :restricted,
      approvals: :auto,
      file_scope: nil,
      allowed_tools: []
    },
    extensions: []
  ]

  @type t :: %__MODULE__{
          capability_id: String.t(),
          input: map(),
          connection_id: String.t() | nil,
          actor_id: String.t() | nil,
          tenant_id: String.t() | nil,
          environment: atom() | String.t() | nil,
          trace_id: String.t() | nil,
          allowed_operations: [String.t()],
          sandbox: Gateway.sandbox_t(),
          target_id: String.t() | nil,
          aggregator_id: String.t() | nil,
          aggregator_epoch: pos_integer() | nil,
          extensions: keyword()
        }

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = request), do: request

  def new!(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = Map.new(attrs)
    reject_credential_ref!(attrs)

    capability_id =
      Contracts.validate_non_empty_string!(
        Contracts.fetch!(attrs, :capability_id),
        "capability_id"
      )

    struct!(__MODULE__, %{
      capability_id: capability_id,
      input: normalize_input(Contracts.get(attrs, :input, %{})),
      connection_id: optional_string(Contracts.get(attrs, :connection_id), "connection_id"),
      actor_id: optional_string(Contracts.get(attrs, :actor_id), "actor_id"),
      tenant_id: optional_string(Contracts.get(attrs, :tenant_id), "tenant_id"),
      environment: normalize_environment(Contracts.get(attrs, :environment)),
      trace_id: optional_string(Contracts.get(attrs, :trace_id), "trace_id"),
      allowed_operations:
        Contracts.normalize_string_list!(
          Contracts.get(attrs, :allowed_operations, [capability_id]),
          "allowed_operations"
        ),
      sandbox: normalize_sandbox(Contracts.get(attrs, :sandbox, %{})),
      target_id: optional_string(Contracts.get(attrs, :target_id), "target_id"),
      aggregator_id: optional_string(Contracts.get(attrs, :aggregator_id), "aggregator_id"),
      aggregator_epoch: normalize_aggregator_epoch(Contracts.get(attrs, :aggregator_epoch)),
      extensions: normalize_extensions(Contracts.get(attrs, :extensions, []))
    })
  end

  def new!(attrs) do
    raise ArgumentError,
          "invocation_request attrs must be a map or keyword list, got: #{inspect(attrs)}"
  end

  @spec to_opts(t()) :: keyword()
  def to_opts(%__MODULE__{} = request) do
    [
      {:connection_id, request.connection_id},
      {:actor_id, request.actor_id},
      {:tenant_id, request.tenant_id},
      {:environment, request.environment},
      {:trace_id, request.trace_id},
      {:allowed_operations, request.allowed_operations},
      {:sandbox, request.sandbox},
      {:target_id, request.target_id},
      {:aggregator_id, request.aggregator_id},
      {:aggregator_epoch, request.aggregator_epoch}
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Kernel.++(request.extensions)
  end

  defp normalize_input(input) when is_map(input), do: input

  defp normalize_input(input) do
    raise ArgumentError, "input must be a map, got: #{inspect(input)}"
  end

  defp optional_string(nil, _field_name), do: nil

  defp optional_string(value, field_name) do
    Contracts.validate_non_empty_string!(value, field_name)
  end

  defp normalize_environment(nil), do: nil
  defp normalize_environment(value) when is_atom(value), do: value

  defp normalize_environment(value) when is_binary(value) do
    Contracts.validate_non_empty_string!(value, "environment")
  end

  defp normalize_environment(value) do
    raise ArgumentError, "environment must be an atom or string, got: #{inspect(value)}"
  end

  defp normalize_sandbox(sandbox) when is_map(sandbox) do
    Gateway.new!(%{runtime_class: :direct, sandbox: sandbox}).sandbox
  end

  defp normalize_sandbox(sandbox) do
    raise ArgumentError, "sandbox must be a map, got: #{inspect(sandbox)}"
  end

  defp normalize_aggregator_epoch(nil), do: nil

  defp normalize_aggregator_epoch(aggregator_epoch)
       when is_integer(aggregator_epoch) and aggregator_epoch > 0,
       do: aggregator_epoch

  defp normalize_aggregator_epoch(aggregator_epoch) do
    raise ArgumentError,
          "aggregator_epoch must be a positive integer, got: #{inspect(aggregator_epoch)}"
  end

  defp normalize_extensions(extensions) when is_list(extensions) do
    if not Keyword.keyword?(extensions) do
      raise ArgumentError, "extensions must be a keyword list, got: #{inspect(extensions)}"
    end

    reserved_keys =
      extensions
      |> Keyword.keys()
      |> Enum.uniq()
      |> Enum.filter(&(&1 in @reserved_extension_keys))

    if reserved_keys != [] do
      raise ArgumentError,
            "extensions must not redefine reserved invoke fields: #{inspect(reserved_keys)}"
    end

    extensions
  end

  defp normalize_extensions(extensions) do
    raise ArgumentError, "extensions must be a keyword list, got: #{inspect(extensions)}"
  end

  defp reject_credential_ref!(attrs) do
    if Map.has_key?(attrs, :credential_ref) or Map.has_key?(attrs, "credential_ref") do
      raise ArgumentError, "credential_ref is not part of the public invocation contract"
    end
  end
end
