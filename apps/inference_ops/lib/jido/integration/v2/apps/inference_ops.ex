defmodule Jido.Integration.V2.Apps.InferenceOps do
  @moduledoc """
  Thin proof wrapper above `Jido.Integration.V2` for the first live inference
  runtime family.
  """

  alias Jido.Integration.V2
  alias Jido.Integration.V2.InferenceRequest

  @spec register_self_hosted_backend() :: :ok | {:error, term()}
  def register_self_hosted_backend do
    case LlamaCppEx.register_backend() do
      :ok -> :ok
      {:error, :already_registered} -> :ok
      {:error, {:already_registered, _module}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec run_cloud_proof(keyword()) :: {:ok, map()} | {:error, term()}
  def run_cloud_proof(opts \\ []) do
    request = Keyword.get_lazy(opts, :request, fn -> cloud_request(opts) end)
    V2.invoke_inference(request, runtime_opts(opts))
  end

  @spec run_self_hosted_proof(keyword()) :: {:ok, map()} | {:error, term()}
  def run_self_hosted_proof(opts \\ []) do
    with :ok <- register_self_hosted_backend() do
      request = Keyword.get_lazy(opts, :request, fn -> self_hosted_request(opts) end)
      V2.invoke_inference(request, runtime_opts(opts))
    end
  end

  @spec review_packet(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def review_packet(run_id, opts \\ %{}) when is_binary(run_id) and is_map(opts) do
    V2.review_packet(run_id, opts)
  end

  defp cloud_request(opts) do
    InferenceRequest.new!(%{
      request_id: Keyword.get(opts, :request_id, "req-inference-ops-cloud"),
      operation: Keyword.get(opts, :operation, :generate_text),
      messages: [
        %{
          role: "user",
          content: Keyword.get(opts, :message, "Summarize the cloud proof flow")
        }
      ],
      prompt: nil,
      model_preference: %{
        provider: Keyword.get(opts, :provider, "openai"),
        id: Keyword.get(opts, :model_id, "gpt-4o-mini")
      },
      target_preference: %{target_class: "cloud_provider"},
      stream?: Keyword.get(opts, :stream?, false),
      tool_policy: %{},
      output_constraints: %{},
      metadata: %{tenant_id: Keyword.get(opts, :tenant_id, "tenant-inference-ops-cloud")}
    })
  end

  defp self_hosted_request(opts) do
    boot_spec = Keyword.fetch!(opts, :boot_spec)

    InferenceRequest.new!(%{
      request_id: Keyword.get(opts, :request_id, "req-inference-ops-self-hosted"),
      operation: Keyword.get(opts, :operation, :stream_text),
      messages: [
        %{
          role: "user",
          content: Keyword.get(opts, :message, "Stream the self-hosted proof flow")
        }
      ],
      prompt: nil,
      model_preference: %{
        provider: "openai",
        id: Keyword.get(opts, :model_id, "fixture-llama")
      },
      target_preference: %{
        target_class: "self_hosted_endpoint",
        backend: Keyword.get(opts, :backend, "llama_cpp"),
        boot_spec: boot_spec
      },
      stream?: Keyword.get(opts, :stream?, true),
      tool_policy: %{},
      output_constraints: %{},
      metadata: %{tenant_id: Keyword.get(opts, :tenant_id, "tenant-inference-ops-self-hosted")}
    })
  end

  defp runtime_opts(opts) do
    Keyword.drop(
      opts,
      [
        :backend,
        :boot_spec,
        :message,
        :model_id,
        :operation,
        :provider,
        :request,
        :request_id,
        :stream?,
        :tenant_id
      ]
    )
  end
end
