defmodule Jido.Integration.V2.Run do
  @moduledoc """
  Durable record of requested work.
  """

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.CredentialRef

  @enforce_keys [:run_id, :capability_id, :runtime_class, :status, :input, :credential_ref]
  defstruct [
    :run_id,
    :capability_id,
    :runtime_class,
    :status,
    :input,
    :credential_ref,
    :target_id,
    :result,
    :inserted_at,
    :updated_at,
    artifact_refs: []
  ]

  @type t :: %__MODULE__{
          run_id: String.t(),
          capability_id: String.t(),
          runtime_class: Contracts.runtime_class(),
          status: Contracts.run_status(),
          input: map(),
          credential_ref: CredentialRef.t(),
          target_id: String.t() | nil,
          artifact_refs: [ArtifactRef.t()],
          result: map() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)
    timestamp = Map.get(attrs, :inserted_at, Contracts.now())

    struct!(__MODULE__, %{
      run_id: Map.get(attrs, :run_id, Contracts.next_id("run")),
      capability_id: Map.fetch!(attrs, :capability_id),
      runtime_class: Contracts.validate_runtime_class!(Map.fetch!(attrs, :runtime_class)),
      status: Contracts.validate_run_status!(Map.get(attrs, :status, :accepted)),
      input: Map.fetch!(attrs, :input),
      credential_ref: Map.fetch!(attrs, :credential_ref),
      target_id: Map.get(attrs, :target_id),
      result: Map.get(attrs, :result),
      inserted_at: timestamp,
      updated_at: Map.get(attrs, :updated_at, timestamp),
      artifact_refs: Map.get(attrs, :artifact_refs, [])
    })
  end
end
