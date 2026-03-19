defmodule Jido.Integration.V2.ConsumerProjection do
  @moduledoc """
  Shared projection rules for generated consumer surfaces built from authored manifests.
  """

  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.InvocationRequest
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.OperationSpec

  @default_invoker :"Elixir.Jido.Integration.V2"

  defmodule ActionProjection do
    @moduledoc """
    Projected metadata for a generated `Jido.Action` surface.
    """

    @enforce_keys [
      :connector_module,
      :plugin_module,
      :module,
      :operation_id,
      :action_name,
      :description,
      :category,
      :tags,
      :schema,
      :output_schema
    ]
    defstruct [
      :connector_module,
      :plugin_module,
      :module,
      :operation_id,
      :action_name,
      :description,
      :category,
      :tags,
      :schema,
      :output_schema
    ]

    @type t :: %__MODULE__{
            connector_module: module(),
            plugin_module: module(),
            module: module(),
            operation_id: String.t(),
            action_name: String.t(),
            description: String.t(),
            category: String.t(),
            tags: [String.t()],
            schema: term(),
            output_schema: term()
          }
  end

  defmodule PluginProjection do
    @moduledoc """
    Projected metadata for a generated `Jido.Plugin` bundle.
    """

    @enforce_keys [
      :connector_module,
      :module,
      :name,
      :state_key,
      :description,
      :category,
      :tags,
      :config_schema,
      :actions
    ]
    defstruct [
      :connector_module,
      :module,
      :name,
      :state_key,
      :description,
      :category,
      :tags,
      :config_schema,
      :actions
    ]

    @type t :: %__MODULE__{
            connector_module: module(),
            module: module(),
            name: String.t(),
            state_key: atom(),
            description: String.t(),
            category: String.t(),
            tags: [String.t()],
            config_schema: term(),
            actions: [module()]
          }
  end

  @spec action_projection!(module(), String.t()) :: ActionProjection.t()
  def action_projection!(connector_module, operation_id)
      when is_atom(connector_module) and is_binary(operation_id) do
    manifest = fetch_manifest!(connector_module)
    operation = fetch_operation!(manifest, operation_id)

    %ActionProjection{
      connector_module: connector_module,
      plugin_module: plugin_module(connector_module),
      module: action_module(connector_module, operation),
      operation_id: operation.operation_id,
      action_name: action_name(operation),
      description: operation.description || "Generated action for #{operation.operation_id}",
      category: manifest.catalog.category,
      tags: action_tags(manifest, operation),
      schema: operation.input_schema,
      output_schema: operation.output_schema
    }
  end

  @spec plugin_projection!(module()) :: PluginProjection.t()
  def plugin_projection!(connector_module) when is_atom(connector_module) do
    manifest = fetch_manifest!(connector_module)

    %PluginProjection{
      connector_module: connector_module,
      module: plugin_module(connector_module),
      name: plugin_name(manifest),
      state_key: plugin_state_key(manifest),
      description: "Generated plugin bundle for #{manifest.catalog.display_name}",
      category: manifest.catalog.category,
      tags: plugin_tags(manifest),
      config_schema: plugin_config_schema(manifest),
      actions: action_modules(connector_module)
    }
  end

  @spec action_module(module(), String.t() | OperationSpec.t()) :: module()
  def action_module(connector_module, operation_id_or_spec)

  def action_module(connector_module, %OperationSpec{name: name})
      when is_atom(connector_module) do
    Module.concat([connector_module, Generated, Actions, Macro.camelize(name)])
  end

  def action_module(connector_module, operation_id) when is_atom(connector_module) do
    connector_module
    |> fetch_manifest!()
    |> fetch_operation!(operation_id)
    |> then(&action_module(connector_module, &1))
  end

  @spec action_modules(module()) :: [module()]
  def action_modules(connector_module) when is_atom(connector_module) do
    connector_module
    |> fetch_manifest!()
    |> Map.fetch!(:operations)
    |> Enum.map(&action_module(connector_module, &1))
  end

  @spec plugin_module(module()) :: module()
  def plugin_module(connector_module) when is_atom(connector_module) do
    Module.concat([connector_module, Generated, Plugin])
  end

  @spec action_opts(ActionProjection.t()) :: keyword()
  def action_opts(%ActionProjection{} = projection) do
    [
      name: projection.action_name,
      description: projection.description,
      category: projection.category,
      tags: projection.tags,
      schema: projection.schema,
      output_schema: projection.output_schema
    ]
  end

  @spec plugin_opts(PluginProjection.t()) :: keyword()
  def plugin_opts(%PluginProjection{} = projection) do
    [
      name: projection.name,
      state_key: projection.state_key,
      actions: projection.actions,
      description: projection.description,
      category: projection.category,
      tags: projection.tags,
      config_schema: projection.config_schema,
      subscriptions: []
    ]
  end

  @spec filtered_actions!(PluginProjection.t(), map()) :: [module()]
  def filtered_actions!(%PluginProjection{actions: actions}, config) when is_map(config) do
    enabled_actions =
      config
      |> Contracts.get(:enabled_actions, [])
      |> Contracts.normalize_string_list!("plugin.enabled_actions")

    if enabled_actions == [] do
      actions
    else
      filter_actions!(actions, enabled_actions)
    end
  end

  @doc false
  @spec invocation_request!(ActionProjection.t(), map(), map()) :: InvocationRequest.t()
  def invocation_request!(%ActionProjection{} = projection, params, context)
      when is_map(params) and is_map(context) do
    invoke_context = invoke_context(context)

    %{
      capability_id: projection.operation_id,
      input: Map.drop(params, [:connection_id, "connection_id"]),
      connection_id: resolve_connection_id(projection, params, context, invoke_context),
      actor_id: read_invoke_value(invoke_context, context, :actor_id),
      tenant_id: read_invoke_value(invoke_context, context, :tenant_id),
      environment: read_invoke_value(invoke_context, context, :environment),
      trace_id: read_invoke_value(invoke_context, context, :trace_id),
      allowed_operations: read_invoke_value(invoke_context, context, :allowed_operations),
      sandbox: read_invoke_value(invoke_context, context, :sandbox),
      target_id: read_invoke_value(invoke_context, context, :target_id),
      aggregator_id: read_invoke_value(invoke_context, context, :aggregator_id),
      aggregator_epoch: read_invoke_value(invoke_context, context, :aggregator_epoch),
      extensions: read_invoke_value(invoke_context, context, :extensions, [])
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> InvocationRequest.new!()
  end

  def invocation_request!(%ActionProjection{}, params, context) do
    raise ArgumentError,
          "generated actions expect params and context maps, got: #{inspect({params, context})}"
  end

  @spec run_action(ActionProjection.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def run_action(%ActionProjection{} = projection, params, context)
      when is_map(params) and is_map(context) do
    request = invocation_request!(projection, params, context)

    case invoke(request) do
      {:ok, %{output: output}} when is_map(output) ->
        {:ok, output}

      {:ok, response} ->
        {:error, {:invalid_invoke_response, response}}

      {:error, _reason} = error ->
        error
    end
  end

  def run_action(%ActionProjection{}, params, context) do
    raise ArgumentError,
          "generated actions expect params and context maps, got: #{inspect({params, context})}"
  end

  defp fetch_manifest!(connector_module) do
    manifest = connector_module.manifest()

    if match?(%Manifest{}, manifest) do
      validate_generated_action_projections!(connector_module, manifest)
      manifest
    else
      raise ArgumentError,
            "connector module #{inspect(connector_module)} must return a manifest, got: #{inspect(manifest)}"
    end
  end

  defp validate_generated_action_projections!(connector_module, %Manifest{} = manifest) do
    operations = manifest.operations

    duplicate_modules =
      operations
      |> Enum.map(&action_module(connector_module, &1))
      |> duplicate_values()

    duplicate_action_names =
      operations
      |> Enum.map(&action_name/1)
      |> duplicate_values()

    if duplicate_modules == [] and duplicate_action_names == [] do
      :ok
    else
      details =
        []
        |> append_duplicate_detail("modules", duplicate_modules)
        |> append_duplicate_detail("action names", duplicate_action_names)
        |> Enum.join(", ")

      raise ArgumentError,
            "generated consumer action projections must be unique within a connector, duplicate #{details}"
    end
  end

  defp fetch_operation!(manifest, operation_id) do
    Manifest.fetch_operation(manifest, operation_id) ||
      raise ArgumentError, "unknown authored operation #{inspect(operation_id)}"
  end

  defp action_name(%OperationSpec{jido: jido, operation_id: operation_id}) do
    jido
    |> Contracts.get(:action, %{})
    |> Contracts.get(:name, String.replace(operation_id, ".", "_"))
    |> Contracts.validate_non_empty_string!("operation.jido.action.name")
  end

  defp action_tags(manifest, operation) do
    manifest.catalog.tags
    |> Kernel.++([manifest.connector, Atom.to_string(operation.runtime_class)])
    |> Enum.uniq()
  end

  defp plugin_name(manifest), do: normalize_identifier(manifest.connector)

  defp plugin_state_key(manifest) do
    manifest.connector
    |> normalize_identifier()
    |> String.to_atom()
  end

  defp plugin_tags(manifest) do
    manifest.catalog.tags
    |> Kernel.++([manifest.connector, "generated"])
    |> Enum.uniq()
  end

  defp plugin_config_schema(%Manifest{} = manifest) do
    connection_id_schema =
      Zoi.string(description: "Durable connection_id binding for generated connector actions")

    connection_id_schema =
      case manifest.auth.binding_kind do
        :connection_id -> connection_id_schema
        _other -> connection_id_schema |> Zoi.optional()
      end

    Contracts.ordered_object!(
      connection_id: connection_id_schema,
      enabled_actions:
        Zoi.list(Zoi.string(), description: "Optional subset of generated actions to enable")
        |> Zoi.default([])
    )
  end

  defp normalize_identifier(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    |> Contracts.validate_non_empty_string!("generated consumer identifier")
  end

  defp filter_actions!(actions, enabled_actions) do
    unknown_actions =
      Enum.reject(enabled_actions, fn enabled_action ->
        Enum.any?(actions, fn action ->
          enabled_action in action_identifiers(action)
        end)
      end)

    if unknown_actions != [] do
      raise ArgumentError,
            "enabled_actions contains unknown generated actions: #{inspect(unknown_actions)}"
    end

    Enum.map(enabled_actions, fn enabled_action ->
      Enum.find(actions, fn action ->
        enabled_action in action_identifiers(action)
      end)
    end)
  end

  defp action_identifiers(action) do
    [
      safe_action_identifier(action, :name),
      safe_action_identifier(action, :operation_id),
      inspect(action)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp safe_action_identifier(action, function_name) do
    if match?({:module, _module}, Code.ensure_compiled(action)) and
         function_exported?(action, function_name, 0) do
      apply(action, function_name, [])
    end
  end

  defp duplicate_values(values) do
    values
    |> Enum.frequencies()
    |> Enum.filter(fn {_value, count} -> count > 1 end)
    |> Enum.map(fn {value, _count} -> value end)
    |> Enum.sort()
  end

  defp append_duplicate_detail(details, _label, []), do: details

  defp append_duplicate_detail(details, label, values) do
    details ++ ["#{label} #{inspect(values)}"]
  end

  defp invoke_context(context) do
    case Contracts.get(context, :invoke, %{}) do
      %{} = invoke_context ->
        invoke_context

      nil ->
        %{}

      other ->
        raise ArgumentError, "action context invoke entry must be a map, got: #{inspect(other)}"
    end
  end

  defp read_invoke_value(invoke_context, context, key, default \\ nil) do
    Contracts.get(invoke_context, key, Contracts.get(context, key, default))
  end

  defp resolve_connection_id(projection, params, context, invoke_context) do
    [
      Contracts.get(params, :connection_id),
      read_invoke_value(invoke_context, context, :connection_id),
      connection_id_from_map(Contracts.get(context, :plugin_config, %{})),
      connection_id_from_map(Contracts.get(context, :config, %{})),
      connection_id_from_plugin_spec(Contracts.get(context, :plugin_spec)),
      connection_id_from_agent_config(projection, context, invoke_context)
    ]
    |> Enum.find(&present_string?/1)
  end

  defp connection_id_from_plugin_spec(%{config: config}) when is_map(config),
    do: connection_id_from_map(config)

  defp connection_id_from_plugin_spec(_other), do: nil

  defp connection_id_from_agent_config(projection, context, invoke_context) do
    agent_module = read_invoke_value(invoke_context, context, :agent_module)

    if is_atom(agent_module) and function_exported?(agent_module, :plugin_config, 1) do
      agent_module
      |> then(& &1.plugin_config(projection.plugin_module))
      |> then(&connection_id_from_map(&1 || %{}))
    end
  rescue
    _error -> nil
  end

  defp connection_id_from_map(%{} = config), do: Contracts.get(config, :connection_id)
  defp connection_id_from_map(_other), do: nil

  defp present_string?(value), do: is_binary(value) and byte_size(String.trim(value)) > 0

  defp invoke(request) do
    if function_exported?(@default_invoker, :invoke, 1) do
      :erlang.apply(@default_invoker, :invoke, [request])
    else
      {:error, {:invalid_invoker, @default_invoker}}
    end
  end
end
