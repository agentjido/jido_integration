defmodule Jido.Integration.V2.StreamRuntimeTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.RuntimeResult
  alias Jido.Integration.V2.StreamRuntime

  defmodule TestProvider do
    @behaviour Jido.Integration.V2.StreamRuntime.Provider

    @impl true
    def reuse_key(capability, input, context) do
      {capability.id, input.symbol, context.credential_lease.subject}
    end

    @impl true
    def open_stream(_capability, input, _context) do
      {:ok, %{stream_id: "stream-1", symbol: input.symbol, cursor: 0}}
    end

    @impl true
    def pull(_capability, stream, input, _context) do
      items =
        for seq <- (stream.cursor + 1)..(stream.cursor + input.limit) do
          %{seq: seq, symbol: stream.symbol}
        end

      updated_stream = %{stream | cursor: stream.cursor + input.limit}

      {:ok, %{items: items, cursor: updated_stream.cursor}, updated_stream}
    end
  end

  defmodule InstrumentedProvider do
    @behaviour Jido.Integration.V2.StreamRuntime.Provider

    @impl true
    def reuse_key(capability, input, context) do
      {capability.id, input.symbol, context.credential_lease.credential_ref_id}
    end

    @impl true
    def open_stream(_capability, input, _context) do
      {:ok, %{stream_id: "stream-instrumented", symbol: input.symbol, cursor: 0}}
    end

    @impl true
    def pull(_capability, stream, input, _context) do
      updated_stream = %{stream | cursor: stream.cursor + input.limit}

      {:ok,
       RuntimeResult.new!(%{
         output: %{items: [%{seq: updated_stream.cursor}], cursor: updated_stream.cursor},
         events: [
           %{type: "connector.test.stream_pulled", payload: %{cursor: updated_stream.cursor}}
         ]
       }), updated_stream}
    end
  end

  setup do
    StreamRuntime.reset!()
    :ok
  end

  test "reuses stream state for repeated pulls" do
    capability =
      Capability.new!(%{
        id: "market.ticks.pull",
        connector: "market_data",
        runtime_class: :stream,
        kind: :stream_read,
        transport_profile: :market_feed,
        handler: TestProvider
      })

    context = %{
      credential_ref: CredentialRef.new!(%{id: "cred-1", subject: "desk-a"}),
      credential_lease:
        CredentialLease.new!(%{
          lease_id: "lease-1",
          credential_ref_id: "cred-1",
          subject: "desk-a",
          scopes: ["market:read"],
          payload: %{token: "lease-token"},
          issued_at: ~U[2026-03-09 12:00:00Z],
          expires_at: ~U[2026-03-09 12:05:00Z]
        })
    }

    assert {:ok, first} = StreamRuntime.execute(capability, %{symbol: "ES", limit: 2}, context)
    assert {:ok, second} = StreamRuntime.execute(capability, %{symbol: "ES", limit: 2}, context)

    assert first.runtime_ref_id == second.runtime_ref_id
    assert first.output.cursor == 2
    assert second.output.cursor == 4
  end

  test "preserves connector-emitted stream events" do
    capability =
      Capability.new!(%{
        id: "market.instrumented.pull",
        connector: "market_data",
        runtime_class: :stream,
        kind: :stream_read,
        transport_profile: :market_feed,
        handler: InstrumentedProvider
      })

    context = %{
      credential_ref: CredentialRef.new!(%{id: "cred-1", subject: "desk-a"}),
      credential_lease:
        CredentialLease.new!(%{
          lease_id: "lease-1",
          credential_ref_id: "cred-1",
          subject: "desk-a",
          scopes: ["market:read"],
          payload: %{token: "lease-token"},
          issued_at: ~U[2026-03-09 12:00:00Z],
          expires_at: ~U[2026-03-09 12:05:00Z]
        })
    }

    assert {:ok, result} = StreamRuntime.execute(capability, %{symbol: "ES", limit: 1}, context)
    assert Enum.any?(result.events, &(&1.type == "connector.test.stream_pulled"))
  end
end
