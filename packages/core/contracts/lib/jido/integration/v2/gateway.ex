defmodule Jido.Integration.V2.Gateway do
  @moduledoc """
  Canonical gateway input for pre-dispatch admission and in-run execution policy.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.CredentialRef

  @default_sandbox %{
    level: :standard,
    egress: :restricted,
    approvals: :auto,
    file_scope: nil,
    allowed_tools: []
  }

  @enforce_keys [:runtime_class]
  defstruct [
    :actor_id,
    :tenant_id,
    :environment,
    :trace_id,
    :credential_ref,
    :runtime_class,
    allowed_operations: [],
    sandbox: @default_sandbox,
    metadata: %{}
  ]

  @type sandbox_t :: %{
          level: Contracts.sandbox_level(),
          egress: Contracts.egress_policy(),
          approvals: Contracts.approvals(),
          file_scope: String.t() | nil,
          allowed_tools: [String.t()]
        }

  @type t :: %__MODULE__{
          actor_id: String.t() | nil,
          tenant_id: String.t() | nil,
          environment: atom() | String.t() | nil,
          trace_id: String.t() | nil,
          credential_ref: CredentialRef.t() | nil,
          runtime_class: Contracts.runtime_class(),
          allowed_operations: [String.t()],
          sandbox: sandbox_t(),
          metadata: map()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)

    struct!(__MODULE__, %{
      actor_id: optional_string(Contracts.get(attrs, :actor_id)),
      tenant_id: optional_string(Contracts.get(attrs, :tenant_id)),
      environment: normalize_environment(Contracts.get(attrs, :environment)),
      trace_id: optional_string(Contracts.get(attrs, :trace_id)),
      credential_ref: normalize_credential_ref(Contracts.get(attrs, :credential_ref)),
      runtime_class: Contracts.validate_runtime_class!(Contracts.fetch!(attrs, :runtime_class)),
      allowed_operations:
        Contracts.normalize_string_list!(
          Contracts.get(attrs, :allowed_operations, []),
          "allowed_operations"
        ),
      sandbox: normalize_sandbox(Contracts.get(attrs, :sandbox, %{})),
      metadata: normalize_metadata(Contracts.get(attrs, :metadata, %{}))
    })
  end

  defp optional_string(nil), do: nil
  defp optional_string(value), do: Contracts.validate_non_empty_string!(value, "gateway")

  defp normalize_environment(nil), do: nil
  defp normalize_environment(value) when is_atom(value), do: value

  defp normalize_environment(value) when is_binary(value),
    do: Contracts.validate_non_empty_string!(value, "environment")

  defp normalize_environment(value) do
    raise ArgumentError, "environment must be an atom or string, got: #{inspect(value)}"
  end

  defp normalize_credential_ref(nil), do: nil
  defp normalize_credential_ref(%CredentialRef{} = credential_ref), do: credential_ref

  defp normalize_credential_ref(value) do
    raise ArgumentError, "credential_ref must be a CredentialRef, got: #{inspect(value)}"
  end

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata

  defp normalize_metadata(metadata) do
    raise ArgumentError, "gateway metadata must be a map, got: #{inspect(metadata)}"
  end

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

  defp normalize_sandbox(sandbox) do
    raise ArgumentError, "sandbox must be a map, got: #{inspect(sandbox)}"
  end

  defp normalize_file_scope(nil), do: nil

  defp normalize_file_scope(file_scope),
    do: Contracts.validate_non_empty_string!(file_scope, "sandbox.file_scope")
end
