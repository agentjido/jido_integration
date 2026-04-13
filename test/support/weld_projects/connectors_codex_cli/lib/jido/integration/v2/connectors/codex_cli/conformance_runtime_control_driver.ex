defmodule Jido.Integration.V2.Connectors.CodexCli.ConformanceRuntimeControlDriver do
  @moduledoc false

  @table __MODULE__

  alias Jido.Integration.V2.ArtifactBuilder
  alias Jido.Integration.V2.RuntimeResult
  alias Jido.RuntimeControl.{ExecutionResult, RunRequest, SessionHandle}

  @spec reset!() :: :ok
  def reset! do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ok
  end

  @spec start_session(keyword()) :: {:ok, SessionHandle.t()}
  def start_session(opts) when is_list(opts) do
    ensure_table!()
    session_id = "asm-session-" <> Integer.to_string(System.unique_integer([:positive]))
    true = :ets.insert(@table, {session_id, 0})

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
  def run(%SessionHandle{} = session, %RunRequest{} = request, opts) when is_list(opts) do
    capability = Keyword.fetch!(opts, :capability)

    case capability.id do
      "market.ticks.pull" ->
        run_market_data(session, request, opts)

      _other ->
        run_codex_cli(session, request, opts)
    end
  end

  @spec stop_session(SessionHandle.t()) :: :ok
  def stop_session(%SessionHandle{session_id: session_id}) do
    ensure_table!()
    :ets.delete(@table, session_id)
    :ok
  end

  defp run_codex_cli(%SessionHandle{} = session, %RunRequest{} = request, opts) do
    turn = advance_counter!(session.session_id, 1)
    capability = Keyword.fetch!(opts, :capability)
    context = Keyword.fetch!(opts, :context)
    prompt = Map.fetch!(Keyword.fetch!(opts, :input), :prompt)
    workspace = request.cwd
    tool = opts |> Keyword.get(:allowed_tools, []) |> List.first()
    auth_binding = ArtifactBuilder.digest(credential_value(context.credential_lease.payload))
    reply = "codex(#{context.credential_lease.subject}) turn #{turn}: #{String.downcase(prompt)}"

    artifact =
      ArtifactBuilder.build!(
        run_id: context.run_id,
        attempt_id: context.attempt_id,
        artifact_type: :event_log,
        key: "codex_cli/#{context.run_id}/#{context.attempt_id}/turn_#{turn}.term",
        content: %{
          prompt: prompt,
          reply: reply,
          turn: turn,
          workspace: workspace,
          tool: tool
        },
        metadata: %{
          connector: "codex_cli",
          capability_id: capability.id,
          session_id: session.session_id,
          auth_binding: auth_binding
        }
      )

    runtime_result =
      RuntimeResult.new!(%{
        output: %{
          reply: reply,
          turn: turn,
          workspace: workspace,
          auth_binding: auth_binding,
          approval_mode: context.policy_inputs.execution.sandbox.approvals
        },
        runtime_ref_id: session.session_id,
        events: [
          %{
            type: lifecycle_event_type(:session, Keyword.get(opts, :lifecycle, :started)),
            payload: %{provider: session.provider},
            session_id: session.session_id,
            runtime_ref_id: session.session_id
          },
          %{
            type: "connector.codex_cli.turn.completed",
            stream: :assistant,
            payload: %{
              turn: turn,
              workspace: workspace,
              tool: tool,
              auth_binding: auth_binding
            },
            session_id: session.session_id,
            runtime_ref_id: session.session_id
          }
        ],
        artifacts: [artifact]
      })

    execution_result(session, context, reply, runtime_result, opts)
  end

  defp run_market_data(%SessionHandle{} = session, %RunRequest{} = _request, opts) do
    capability = Keyword.fetch!(opts, :capability)
    context = Keyword.fetch!(opts, :context)
    input = Keyword.fetch!(opts, :input)
    symbol = Map.fetch!(input, :symbol)
    limit = Map.get(input, :limit, 1)
    venue = Map.get(input, :venue, "demo")
    cursor = advance_counter!(session.session_id, limit)
    auth_binding = ArtifactBuilder.digest(credential_value(context.credential_lease.payload))

    items =
      for seq <- (cursor - limit + 1)..cursor do
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
        key: "market_data/#{context.run_id}/#{context.attempt_id}/batch_#{cursor}.term",
        content: %{
          symbol: symbol,
          venue: venue,
          cursor: cursor,
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
          cursor: cursor,
          items: items,
          auth_binding: auth_binding
        },
        runtime_ref_id: session.session_id,
        events: [
          %{
            type: lifecycle_event_type(:stream, Keyword.get(opts, :lifecycle, :started)),
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
              cursor: cursor,
              batch_size: limit,
              auth_binding: auth_binding
            },
            session_id: session.session_id,
            runtime_ref_id: session.session_id
          }
        ],
        artifacts: [artifact]
      })

    execution_result(session, context, "#{symbol} batch #{cursor}", runtime_result, opts)
  end

  defp execution_result(%SessionHandle{} = session, context, text, runtime_result, opts) do
    {:ok,
     ExecutionResult.new!(%{
       run_id: Keyword.get(opts, :run_id, context.run_id),
       session_id: session.session_id,
       runtime_id: :asm,
       provider: session.provider,
       status: :completed,
       text: text,
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

  defp lifecycle_event_type(:session, :reused), do: "session.reused"
  defp lifecycle_event_type(:session, _other), do: "session.started"
  defp lifecycle_event_type(:stream, :reused), do: "stream.reused"
  defp lifecycle_event_type(:stream, _other), do: "stream.started"

  defp advance_counter!(session_id, step) do
    ensure_table!()
    :ets.update_counter(@table, session_id, {2, step})
  end

  defp credential_value(payload) do
    case Map.get(payload, :access_token) || Map.get(payload, :api_key) do
      nil -> raise ArgumentError, "missing credential token payload"
      value -> value
    end
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

      _table ->
        @table
    end
  rescue
    ArgumentError ->
      @table
  end
end
