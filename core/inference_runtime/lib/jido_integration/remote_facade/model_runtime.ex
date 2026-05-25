defmodule JidoIntegration.RemoteFacade.ModelRuntime do
  @moduledoc """
  Jido Integration-owned model runtime facade for distributed StackLab profiles.

  Model invocation is an accepted-ref/readback seam. The default implementation
  uses the deterministic inference runtime so local distributed proof does not
  require live provider credentials.
  """

  alias Jido.Integration.InferenceRuntime
  alias Jido.Integration.ModelInvocation.{Receipt, StreamFragment}

  @owner_group {__MODULE__, :model_runtime}

  @spec owner_group() :: {module(), :model_runtime}
  def owner_group, do: @owner_group

  @spec submit_invocation(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def submit_invocation(request, opts \\ []) when is_map(request) and is_list(opts) do
    case InferenceRuntime.invoke(request, opts) do
      {:ok, %{receipt: %Receipt{} = receipt} = result} ->
        {:ok,
         %{
           "status" => "accepted",
           "accepted_ref" => receipt.invocation_ref,
           "receipt" => Receipt.dump(receipt),
           "stream_fragments" => dump_fragments(Map.get(result, :stream_fragments, [])),
           "async_contract" => "accepted_ref_plus_readback"
         }}

      {:error, reason} ->
        {:error, error(:model_invocation_failed, %{"reason" => format_reason(reason)})}
    end
  rescue
    error in ArgumentError ->
      {:error, error(:invalid_envelope, %{"reason" => Exception.message(error)})}
  end

  defp format_reason(%_{} = reason), do: Exception.message(reason)
  defp format_reason(reason), do: inspect(reason)

  @spec read_invocation(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def read_invocation(ref, opts \\ []) when is_binary(ref) and is_list(opts) do
    if String.trim(ref) == "" do
      {:error, error(:invalid_envelope, %{"missing_field" => "invocation_ref"})}
    else
      {:ok,
       %{
         "invocation_ref" => ref,
         "status" => Keyword.get(opts, :status, "accepted"),
         "owner" => "jido_integration",
         "terminal?" => Keyword.get(opts, :terminal?, false)
       }}
    end
  end

  defp dump_fragments(fragments) when is_list(fragments) do
    Enum.map(fragments, fn
      %StreamFragment{} = fragment -> StreamFragment.dump(fragment)
      value -> value
    end)
  end

  defp error(code, attrs) do
    Map.merge(
      %{
        "code" => Atom.to_string(code),
        "owner" => "jido_integration",
        "facade" => "model_runtime"
      },
      attrs
    )
  end
end
