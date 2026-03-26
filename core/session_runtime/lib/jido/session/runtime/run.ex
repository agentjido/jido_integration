defmodule Jido.Session.Runtime.Run do
  @moduledoc """
  Internal run state tracked by `jido_session` before projection into Harness IR.
  """

  alias Jido.Harness.RunRequest
  alias Jido.Session.Runtime.Session

  @enforce_keys [
    :run_id,
    :session_id,
    :provider,
    :status,
    :prompt,
    :request_metadata,
    :messages,
    :started_at
  ]
  defstruct [
    :run_id,
    :session_id,
    :provider,
    :status,
    :prompt,
    :request_metadata,
    :messages,
    :result_text,
    :started_at,
    :completed_at,
    :duration_ms,
    :stop_reason,
    :metadata
  ]

  @type t :: %__MODULE__{
          run_id: String.t(),
          session_id: String.t(),
          provider: atom(),
          status: atom(),
          prompt: String.t(),
          request_metadata: map(),
          messages: [map()],
          result_text: String.t() | nil,
          started_at: String.t(),
          completed_at: String.t() | nil,
          duration_ms: integer() | nil,
          stop_reason: String.t() | nil,
          metadata: map() | nil
        }

  @spec start(Session.t(), RunRequest.t(), keyword()) :: t()
  def start(%Session{} = session, %RunRequest{} = request, opts \\ []) do
    now = Keyword.get(opts, :timestamp, iso8601_now())

    %__MODULE__{
      run_id: Keyword.get(opts, :run_id, build_id("run")),
      session_id: session.session_id,
      provider: session.provider,
      status: :running,
      prompt: request.prompt,
      request_metadata: normalize_map(request.metadata),
      messages: [%{"role" => "user", "content" => request.prompt}],
      result_text: nil,
      started_at: now,
      completed_at: nil,
      duration_ms: nil,
      stop_reason: nil,
      metadata: %{}
    }
  end

  @spec complete(t(), map()) :: t()
  def complete(%__MODULE__{} = run, attrs) when is_map(attrs) do
    %__MODULE__{
      run
      | status: Map.get(attrs, :status, :completed),
        messages: Map.get(attrs, :messages, run.messages),
        result_text: Map.get(attrs, :result_text),
        completed_at: Map.get(attrs, :completed_at, run.started_at),
        duration_ms: Map.get(attrs, :duration_ms, 0),
        stop_reason: Map.get(attrs, :stop_reason, "completed"),
        metadata: Map.get(attrs, :metadata, %{})
    }
  end

  @spec cancel(t()) :: t()
  def cancel(%__MODULE__{} = run) do
    %__MODULE__{
      run
      | status: :cancelled,
        result_text: run.result_text || "cancelled",
        completed_at: run.completed_at || run.started_at,
        duration_ms: run.duration_ms || 0,
        stop_reason: run.stop_reason || "cancelled"
    }
  end

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_), do: %{}

  defp build_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp iso8601_now do
    DateTime.utc_now() |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()
  end
end
