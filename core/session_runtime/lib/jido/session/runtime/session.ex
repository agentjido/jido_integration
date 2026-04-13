defmodule Jido.Session.Runtime.Session do
  @moduledoc """
  Richer internal session model kept above the shared Runtime Control IR floor.
  """

  @enforce_keys [
    :session_id,
    :provider,
    :session_type,
    :status,
    :metadata,
    :run_ids,
    :inserted_at,
    :updated_at
  ]
  defstruct [
    :session_id,
    :provider,
    :session_type,
    :cwd,
    :status,
    :metadata,
    :run_ids,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          session_id: String.t(),
          provider: atom(),
          session_type: atom(),
          cwd: String.t() | nil,
          status: atom(),
          metadata: map(),
          run_ids: [String.t()],
          inserted_at: String.t(),
          updated_at: String.t()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) when is_list(opts) do
    now = Keyword.get(opts, :timestamp, iso8601_now())

    %__MODULE__{
      session_id: Keyword.get(opts, :session_id, build_id("session")),
      provider: Keyword.get(opts, :provider, :jido_session),
      session_type: Keyword.get(opts, :session_type, :local_echo),
      cwd: Keyword.get(opts, :cwd),
      status: :ready,
      metadata: normalize_map(Keyword.get(opts, :metadata, %{})),
      run_ids: [],
      inserted_at: now,
      updated_at: now
    }
  end

  @spec attach_run(t(), String.t(), String.t()) :: t()
  def attach_run(%__MODULE__{} = session, run_id, timestamp)
      when is_binary(run_id) and is_binary(timestamp) do
    %__MODULE__{
      session
      | run_ids: Enum.uniq(session.run_ids ++ [run_id]),
        updated_at: timestamp
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
