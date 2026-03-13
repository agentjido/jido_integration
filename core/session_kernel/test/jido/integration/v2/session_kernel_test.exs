defmodule Jido.Integration.V2.SessionKernelTest do
  use ExUnit.Case

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.RuntimeResult
  alias Jido.Integration.V2.SessionKernel

  defmodule TestProvider do
    @behaviour Jido.Integration.V2.SessionKernel.Provider

    alias Jido.Integration.V2.Contracts

    @impl true
    def reuse_key(capability, context), do: {capability.id, context.credential_lease.subject}

    @impl true
    def open_session(_capability, context) do
      {:ok,
       %{
         session_id: Contracts.next_id("session"),
         turns: 0,
         subject: context.credential_lease.subject
       }}
    end

    @impl true
    def execute(_capability, session, _input, _context) do
      updated = %{session | turns: session.turns + 1}

      {:ok,
       RuntimeResult.new!(%{
         output: %{turn: updated.turns},
         events: [
           %{type: "connector.test.session_turn", payload: %{turn: updated.turns}}
         ]
       }), updated}
    end
  end

  setup do
    SessionKernel.reset!()
    :ok
  end

  test "reuses the same session for the same subject" do
    capability =
      Capability.new!(%{
        id: "test.session",
        connector: "test",
        runtime_class: :session,
        kind: :session_operation,
        transport_profile: :stdio,
        handler: TestProvider
      })

    context = %{
      credential_ref: CredentialRef.new!(%{id: "cred-1", subject: "desk-a"}),
      credential_lease:
        CredentialLease.new!(%{
          lease_id: "lease-1",
          credential_ref_id: "cred-1",
          subject: "desk-a",
          scopes: ["session:run"],
          payload: %{token: "lease-token"},
          issued_at: ~U[2026-03-09 12:00:00Z],
          expires_at: ~U[2026-03-09 12:05:00Z]
        })
    }

    assert {:ok, first} = SessionKernel.execute(capability, %{}, context)
    assert {:ok, second} = SessionKernel.execute(capability, %{}, context)

    assert first.runtime_ref_id == second.runtime_ref_id
    assert first.output.turn == 1
    assert second.output.turn == 2
    assert Enum.any?(first.events, &(&1.type == "connector.test.session_turn"))
  end
end
