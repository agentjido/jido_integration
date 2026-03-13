defmodule Jido.Integration.Auth.Connection do
  @moduledoc """
  Connection state machine — tracks the lifecycle of an authenticated
  connection between a tenant and a connector.

  ## States

      (new) → installing → connected ──→ degraded ──────┐
                 ↓              ↓           ↓           │
             reauth_required ←─┴───────────┘            │
                 ↓ ↓                                     │
             revoked ←──────────────────────────────────┤
                 ↓                                       │
             installing (re-install)                    │
                                                        ↓
                                                   disabled
                                                        ↓
                                                   installing (recovery)

  All transitions are validated. Invalid transitions return an error.
  Every transition increments the revision counter and appends to the
  actor audit trail.
  """

  @type state ::
          :new | :installing | :connected | :degraded | :reauth_required | :revoked | :disabled

  @type audit_entry :: %{
          actor_id: String.t(),
          from_state: state(),
          to_state: state(),
          timestamp: DateTime.t()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          connector_id: String.t(),
          tenant_id: String.t(),
          state: state(),
          scopes: [String.t()],
          auth_ref: String.t() | nil,
          revision: non_neg_integer(),
          actor_trail: [audit_entry()],
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :connector_id,
    :tenant_id,
    :auth_ref,
    :created_at,
    :updated_at,
    state: :new,
    scopes: [],
    revision: 0,
    actor_trail: []
  ]

  # Valid state transitions: from => [allowed_to_states]
  @transitions %{
    new: [:installing],
    installing: [:connected, :reauth_required, :revoked],
    connected: [:degraded, :reauth_required, :revoked, :disabled],
    degraded: [:connected, :reauth_required, :revoked, :disabled],
    reauth_required: [:installing, :revoked, :disabled],
    revoked: [:installing, :disabled],
    disabled: [:installing]
  }

  @terminal_states [:revoked, :disabled]

  @doc "Create a new connection."
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(connector_id, tenant_id, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      connector_id: connector_id,
      tenant_id: tenant_id,
      state: :new,
      revision: 0,
      actor_trail: [],
      created_at: now,
      updated_at: now
    }
  end

  @doc """
  Transition the connection to a new state.

  Validates the transition against the state machine. Returns
  `{:error, message}` for invalid transitions.
  """
  @spec transition(t(), state(), String.t()) :: {:ok, t()} | {:error, String.t()}
  def transition(%__MODULE__{state: from} = conn, to_state, actor_id) do
    allowed = Map.get(@transitions, from, [])

    if to_state in allowed do
      entry = %{
        actor_id: actor_id,
        from_state: from,
        to_state: to_state,
        timestamp: DateTime.utc_now()
      }

      {:ok,
       %{
         conn
         | state: to_state,
           revision: conn.revision + 1,
           actor_trail: conn.actor_trail ++ [entry],
           updated_at: DateTime.utc_now()
       }}
    else
      {:error, "Invalid transition: #{from} -> #{to_state}"}
    end
  end

  @doc "Check if the connection is in a terminal state."
  @spec terminal?(t()) :: boolean()
  def terminal?(%__MODULE__{state: state}), do: state in @terminal_states

  @doc "Returns valid transitions from the current state."
  @spec valid_transitions(t()) :: [state()]
  def valid_transitions(%__MODULE__{state: state}) do
    Map.get(@transitions, state, [])
  end

  defp generate_id do
    "conn_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
