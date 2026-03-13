defmodule Jido.Integration.V2.CredentialRef do
  @moduledoc """
  Opaque control-plane-owned credential handle.
  """

  @enforce_keys [:id, :subject]
  defstruct [:id, :subject, scopes: [], metadata: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          subject: String.t(),
          scopes: [String.t()],
          metadata: map()
        }

  @spec new!(map()) :: t()
  def new!(attrs) do
    attrs = Map.new(attrs)

    struct!(__MODULE__, %{
      id: Map.fetch!(attrs, :id),
      subject: Map.fetch!(attrs, :subject),
      scopes: Map.get(attrs, :scopes, []),
      metadata: Map.get(attrs, :metadata, %{})
    })
  end
end
