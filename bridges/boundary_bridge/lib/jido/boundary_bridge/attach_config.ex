defmodule Jido.BoundaryBridge.AttachConfig do
  @moduledoc """
  Kernel-neutral attach intent for allocate and reopen requests.
  """

  alias Jido.BoundaryBridge.Contracts
  alias Jido.BoundaryBridge.Schema

  @attach_modes [:attachable, :not_applicable]

  @schema Zoi.struct(
            __MODULE__,
            %{
              mode:
                Contracts.enumish_schema(@attach_modes, "attach.mode")
                |> Zoi.default(:attachable),
              working_directory:
                Contracts.non_empty_string_schema("attach.working_directory")
                |> Zoi.nullish()
                |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t() | nil) :: {:ok, t()} | {:error, Exception.t()}
  def new(nil), do: {:ok, Schema.new!(__MODULE__, @schema, %{})}
  def new(%__MODULE__{} = attach), do: {:ok, attach}
  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs || %{})

  @spec new!(map() | keyword() | t() | nil) :: t()
  def new!(nil), do: Schema.new!(__MODULE__, @schema, %{})
  def new!(%__MODULE__{} = attach), do: attach
  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs || %{})
end
