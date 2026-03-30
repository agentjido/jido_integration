defmodule Jido.Integration.V2.SubjectRef do
  @moduledoc """
  Stable reference to the primary node-local subject a higher-order record is about.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Schema

  @kinds [
    :run,
    :attempt,
    :event,
    :artifact,
    :trigger,
    :capability,
    :target,
    :connection,
    :install
  ]

  @schema Zoi.struct(
            __MODULE__,
            %{
              ref:
                Contracts.non_empty_string_schema("subject_ref.ref")
                |> Zoi.nullish()
                |> Zoi.optional(),
              kind: Contracts.enumish_schema(@kinds, "subject_ref.kind"),
              id: Contracts.non_empty_string_schema("subject_ref.id"),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type kind ::
          :run
          | :attempt
          | :event
          | :artifact
          | :trigger
          | :capability
          | :target
          | :connection
          | :install

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = subject_ref), do: normalize(subject_ref)

  def new(attrs) do
    __MODULE__
    |> Schema.new(@schema, attrs)
    |> Schema.refine_new(&normalize/1)
  end

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = subject_ref),
    do: normalize(subject_ref) |> then(fn {:ok, value} -> value end)

  def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs) |> new!()

  @spec ref(kind(), String.t()) :: String.t()
  def ref(kind, id), do: Contracts.reference_uri("subject", kind, id)

  @spec dump(t()) :: %{ref: String.t(), kind: kind(), id: String.t(), metadata: map()}
  def dump(%__MODULE__{} = subject_ref) do
    %{
      ref: subject_ref.ref,
      kind: subject_ref.kind,
      id: subject_ref.id,
      metadata: subject_ref.metadata
    }
  end

  defp normalize(%__MODULE__{} = subject_ref) do
    expected_ref = ref(subject_ref.kind, subject_ref.id)

    if is_nil(subject_ref.ref) or subject_ref.ref == expected_ref do
      {:ok,
       %__MODULE__{
         subject_ref
         | ref: expected_ref,
           metadata: normalize_metadata(subject_ref.metadata)
       }}
    else
      {:error,
       ArgumentError.exception(
         "subject_ref.ref must match kind and id: #{inspect({subject_ref.kind, subject_ref.id, subject_ref.ref})}"
       )}
    end
  end

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata

  defp normalize_metadata(metadata) do
    raise ArgumentError, "subject_ref.metadata must be a map, got: #{inspect(metadata)}"
  end
end
