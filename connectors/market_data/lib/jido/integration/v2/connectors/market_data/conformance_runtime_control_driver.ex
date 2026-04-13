defmodule Jido.Integration.V2.Connectors.MarketData.ConformanceRuntimeControlDriver do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.RuntimeResult
  alias Jido.RuntimeControl.{ExecutionResult, RunRequest, SessionHandle}

  @spec start_session(keyword()) :: {:ok, SessionHandle.t()}
  def start_session(opts) when is_list(opts) do
    session_id = "asm-stream-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok,
     SessionHandle.new!(%{
       session_id: session_id,
       runtime_id: :asm,
       provider: Keyword.get(opts, :provider),
       status: :ready,
       metadata: %{}
     })}
  end

  @spec run(SessionHandle.t(), RunRequest.t(), keyword()) :: {:ok, ExecutionResult.t()}
  def run(%SessionHandle{} = session, %RunRequest{} = _request, opts) when is_list(opts) do
    capability = Keyword.fetch!(opts, :capability)
    context = Keyword.fetch!(opts, :context)
    input = Keyword.fetch!(opts, :input)
    symbol = Map.fetch!(input, :symbol)
    limit = Map.get(input, :limit, 1)
    venue = Map.get(input, :venue, "demo")
    auth_binding = ArtifactBuilder.digest(context.credential_lease.payload.api_key)

    items =
      for seq <- 1..limit do
        %{
          seq: seq,
          symbol: symbol,
          venue: venue,
          bid: 5_000 + seq,
          ask: 5_001 + seq
        }
      end

    artifact =
      ArtifactBuilder.build!(
        run_id: context.run_id,
        attempt_id: context.attempt_id,
        artifact_type: :log,
        key: "market_data/#{context.run_id}/#{context.attempt_id}/batch_#{limit}.term",
        content: %{
          symbol: symbol,
          venue: venue,
          cursor: limit,
          batch_size: limit,
          items: items
        },
        metadata: %{
          connector: "market_data",
          capability_id: capability.id,
          session_id: session.session_id,
          auth_binding: auth_binding
        }
      )

    runtime_result =
      RuntimeResult.new!(%{
        output: %{
          symbol: symbol,
          venue: venue,
          cursor: limit,
          items: items,
          auth_binding: auth_binding
        },
        runtime_ref_id: session.session_id,
        events: [
          %{
            type: lifecycle_event_type(Keyword.get(opts, :lifecycle, :started)),
            payload: %{provider: session.provider},
            session_id: session.session_id,
            runtime_ref_id: session.session_id
          },
          %{
            type: "connector.market_data.batch.pulled",
            stream: :control,
            payload: %{
              symbol: symbol,
              venue: venue,
              cursor: limit,
              batch_size: limit,
              auth_binding: auth_binding
            },
            session_id: session.session_id,
            runtime_ref_id: session.session_id
          }
        ],
        artifacts: [artifact]
      })

    {:ok,
     ExecutionResult.new!(%{
       run_id: Keyword.get(opts, :run_id, context.run_id),
       session_id: session.session_id,
       runtime_id: :asm,
       provider: session.provider,
       status: :completed,
       text: "#{symbol} batch #{limit}",
       messages: [],
       cost: %{},
       stop_reason: "completed",
       metadata: %{
         "jido_integration" => %{
           runtime_result: runtime_result
         }
       }
     })}
  end

  @spec stop_session(SessionHandle.t()) :: :ok
  def stop_session(_session), do: :ok

  defp lifecycle_event_type(:reused), do: "stream.reused"
  defp lifecycle_event_type(_other), do: "stream.started"
end
