defmodule Jido.BoundaryBridge.BoundarySessionDescriptor do
  @moduledoc """
  Snapshot descriptor for one allocated or reopened boundary session.
  """

  alias Jido.BoundaryBridge.{Contracts, Extensions, PolicyIntent, Refs, Schema}

  @statuses [:starting, :ready, :running, :needs_input, :stopping, :failed]

  @schema Zoi.struct(
            __MODULE__,
            %{
              descriptor_version: Zoi.integer() |> Zoi.default(1),
              boundary_session_id:
                Contracts.non_empty_string_schema(
                  "boundary_session_descriptor.boundary_session_id"
                ),
              backend_kind: Contracts.atomish_schema("boundary_session_descriptor.backend_kind"),
              boundary_class:
                Contracts.atomish_schema("boundary_session_descriptor.boundary_class")
                |> Zoi.nullish()
                |> Zoi.optional(),
              status: Contracts.enumish_schema(@statuses, "boundary_session_descriptor.status"),
              attach_ready?: Zoi.boolean(),
              workspace: Contracts.any_map_schema(),
              attach: Contracts.any_map_schema(),
              checkpointing: Contracts.any_map_schema(),
              policy_intent_echo: Contracts.any_map_schema() |> Zoi.default(%{}),
              refs: Contracts.any_map_schema(),
              extensions: Contracts.any_map_schema() |> Zoi.default(%{}),
              metadata: Contracts.any_map_schema() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
  def new(%__MODULE__{} = descriptor), do: normalize(descriptor)

  def new(attrs) when is_map(attrs) or is_list(attrs) do
    __MODULE__
    |> Schema.new(@schema, prepare_attrs(attrs))
    |> Schema.refine_new(&normalize/1)
  end

  def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

  @spec new!(map() | keyword() | t()) :: t()
  def new!(%__MODULE__{} = descriptor) do
    case normalize(descriptor) do
      {:ok, descriptor} -> descriptor
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, descriptor} -> descriptor
      {:error, %ArgumentError{} = error} -> raise error
    end
  end

  @spec tracing_extension(t()) :: Jido.BoundaryBridge.Extensions.Tracing.t() | nil
  def tracing_extension(%__MODULE__{extensions: extensions}), do: Extensions.tracing(extensions)

  defp normalize(%__MODULE__{} = descriptor) do
    workspace = __MODULE__.Workspace.new!(descriptor.workspace)
    attach = __MODULE__.Attach.new!(descriptor.attach)
    checkpointing = __MODULE__.Checkpointing.new!(descriptor.checkpointing)
    policy_intent_echo = PolicyIntent.new!(descriptor.policy_intent_echo)
    refs = Refs.new!(descriptor.refs)
    extensions = Extensions.validate!(descriptor.extensions)

    descriptor = %__MODULE__{
      descriptor
      | workspace: workspace,
        attach: attach,
        checkpointing: checkpointing,
        policy_intent_echo: policy_intent_echo,
        refs: refs,
        extensions: extensions
    }

    validate_descriptor_version!(descriptor.descriptor_version)
    validate_attach_semantics!(descriptor)

    {:ok, descriptor}
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp prepare_attrs(attrs) do
    attrs
    |> Map.new()
    |> Map.update(:workspace, %{}, &normalize_nested_mapish/1)
    |> Map.update(:attach, %{}, &normalize_nested_mapish/1)
    |> Map.update(:checkpointing, %{}, &normalize_nested_mapish/1)
    |> Map.update(:policy_intent_echo, %{}, &normalize_nested_mapish/1)
    |> Map.update(:refs, %{}, &normalize_nested_mapish/1)
    |> Map.update(:extensions, %{}, &normalize_nested_mapish/1)
    |> Map.update(:metadata, %{}, &normalize_nested_mapish/1)
  end

  defp normalize_nested_mapish(nil), do: nil
  defp normalize_nested_mapish(attrs) when is_list(attrs), do: Map.new(attrs)
  defp normalize_nested_mapish(%_{} = attrs), do: Map.from_struct(attrs)

  defp normalize_nested_mapish(attrs) when is_map(attrs), do: attrs
  defp normalize_nested_mapish(attrs), do: attrs

  defp validate_descriptor_version!(1), do: :ok

  defp validate_descriptor_version!(value) do
    raise ArgumentError, "descriptor_version must be 1, got: #{inspect(value)}"
  end

  defp validate_attach_semantics!(%__MODULE__{
         attach: %{mode: :not_applicable, execution_surface: nil},
         attach_ready?: false
       }),
       do: :ok

  defp validate_attach_semantics!(%__MODULE__{
         attach: %{
           mode: :not_applicable,
           execution_surface: execution_surface
         }
       })
       when not is_nil(execution_surface) do
    raise ArgumentError,
          "attach.execution_surface must be nil when attach.mode == :not_applicable"
  end

  defp validate_attach_semantics!(%__MODULE__{
         attach: %{mode: :not_applicable},
         attach_ready?: true
       }) do
    raise ArgumentError, "attach_ready? must be false when attach.mode == :not_applicable"
  end

  defp validate_attach_semantics!(%__MODULE__{
         attach: %{mode: :attachable, execution_surface: nil},
         attach_ready?: true
       }) do
    raise ArgumentError,
          "attach.execution_surface must be present when attach.mode == :attachable and attach_ready? is true"
  end

  defp validate_attach_semantics!(_descriptor), do: :ok

  defmodule Workspace do
    @moduledoc "Typed workspace projection for one boundary descriptor."

    alias Jido.BoundaryBridge.Contracts
    alias Jido.BoundaryBridge.Schema

    @schema Zoi.struct(
              __MODULE__,
              %{
                workspace_root:
                  Contracts.non_empty_string_schema("workspace.workspace_root")
                  |> Zoi.nullish()
                  |> Zoi.optional(),
                snapshot_ref:
                  Contracts.non_empty_string_schema("workspace.snapshot_ref")
                  |> Zoi.nullish()
                  |> Zoi.optional(),
                artifact_namespace:
                  Contracts.non_empty_string_schema("workspace.artifact_namespace")
                  |> Zoi.nullish()
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
    def new(%__MODULE__{} = workspace), do: {:ok, workspace}
    def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

    @spec new!(map() | keyword() | t()) :: t()
    def new!(%__MODULE__{} = workspace), do: workspace
    def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)
  end

  defmodule Attach do
    @moduledoc "Typed attach projection for one boundary descriptor."

    alias Jido.BoundaryBridge.Contracts
    alias Jido.BoundaryBridge.Schema

    @schema Zoi.struct(
              __MODULE__,
              %{
                mode: Contracts.enumish_schema([:attachable, :not_applicable], "attach.mode"),
                execution_surface:
                  Zoi.any()
                  |> Zoi.nullish()
                  |> Zoi.optional(),
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

    @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
    def new(%__MODULE__{} = attach), do: normalize(attach)

    def new(attrs) when is_map(attrs) or is_list(attrs) do
      __MODULE__
      |> Schema.new(@schema, Map.new(attrs))
      |> Schema.refine_new(&normalize/1)
    end

    def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

    @spec new!(map() | keyword() | t()) :: t()
    def new!(%__MODULE__{} = attach) do
      case normalize(attach) do
        {:ok, attach} -> attach
        {:error, %ArgumentError{} = error} -> raise error
      end
    end

    def new!(attrs) do
      case new(attrs) do
        {:ok, attach} -> attach
        {:error, %ArgumentError{} = error} -> raise error
      end
    end

    defp normalize(%__MODULE__{} = attach) do
      {:ok,
       %__MODULE__{
         attach
         | execution_surface: normalize_execution_surface!(attach.execution_surface)
       }}
    rescue
      error in ArgumentError -> {:error, error}
    end

    defp normalize_execution_surface!(nil), do: nil

    defp normalize_execution_surface!(%CliSubprocessCore.ExecutionSurface{} = execution_surface),
      do: execution_surface

    defp normalize_execution_surface!(execution_surface)
         when is_map(execution_surface) or is_list(execution_surface) do
      execution_surface_opts =
        if is_list(execution_surface), do: execution_surface, else: Map.to_list(execution_surface)

      case CliSubprocessCore.ExecutionSurface.new(execution_surface_opts) do
        {:ok, execution_surface} ->
          execution_surface

        {:error, reason} ->
          raise ArgumentError, "attach.execution_surface is invalid: #{inspect(reason)}"
      end
    end

    defp normalize_execution_surface!(execution_surface) do
      raise ArgumentError,
            "attach.execution_surface must be a CliSubprocessCore.ExecutionSurface, map, or keyword list, got: #{inspect(execution_surface)}"
    end
  end

  defmodule Checkpointing do
    @moduledoc "Typed checkpointing projection for one boundary descriptor."

    alias Jido.BoundaryBridge.Contracts
    alias Jido.BoundaryBridge.Schema

    @schema Zoi.struct(
              __MODULE__,
              %{
                supported?: Zoi.boolean() |> Zoi.default(false),
                last_checkpoint_id:
                  Contracts.non_empty_string_schema("checkpointing.last_checkpoint_id")
                  |> Zoi.nullish()
                  |> Zoi.optional()
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
    def new(%__MODULE__{} = checkpointing), do: {:ok, checkpointing}
    def new(attrs), do: Schema.new(__MODULE__, @schema, attrs)

    @spec new!(map() | keyword() | t()) :: t()
    def new!(%__MODULE__{} = checkpointing), do: checkpointing
    def new!(attrs), do: Schema.new!(__MODULE__, @schema, attrs)
  end
end
