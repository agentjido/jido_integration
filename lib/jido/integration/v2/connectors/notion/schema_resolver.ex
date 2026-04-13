defmodule Jido.Integration.V2.Connectors.Notion.SchemaResolver do
  @moduledoc false

  alias Jido.Integration.V2.Connectors.Notion.SchemaContext
  alias Jido.Integration.V2.Contracts

  @spec resolve_for_input(map(), NotionSDK.Client.t(), map()) ::
          {:ok, SchemaContext.t() | nil} | {:error, term()}
  def resolve_for_input(metadata, client, params)
      when is_map(metadata) and is_map(params) do
    if has_surface_slots?(metadata, :input) do
      resolve(metadata, client, params, nil)
    else
      {:ok, nil}
    end
  end

  @spec resolve_for_output(map(), NotionSDK.Client.t(), map(), map(), SchemaContext.t() | nil) ::
          {:ok, SchemaContext.t() | nil} | {:error, term()}
  def resolve_for_output(metadata, _client, _params, _response, %SchemaContext{} = schema_context)
      when is_map(metadata) do
    if has_surface_slots?(metadata, :output) do
      {:ok, schema_context}
    else
      {:ok, nil}
    end
  end

  def resolve_for_output(metadata, client, params, response, nil)
      when is_map(metadata) and is_map(params) and is_map(response) do
    if has_surface_slots?(metadata, :output) do
      resolve(metadata, client, params, response)
    else
      {:ok, nil}
    end
  end

  defp resolve(metadata, client, params, response) do
    case Contracts.get(metadata, :schema_context_source, :none) do
      :parent_data_source ->
        resolve_parent_data_source(metadata, client, params)

      :page_parent_data_source ->
        resolve_page_parent_data_source(metadata, client, params, response)

      :data_source ->
        resolve_direct_data_source(metadata, client, params)

      :none ->
        {:ok, nil}

      _other ->
        {:ok, nil}
    end
  end

  defp resolve_parent_data_source(metadata, client, params) do
    case path_get(params, ["parent", "data_source_id"]) do
      data_source_id when is_binary(data_source_id) ->
        fetch_data_source_context(
          metadata,
          client,
          data_source_id,
          :parent_data_source,
          nil,
          [:data_source]
        )

      _other ->
        {:ok, nil}
    end
  end

  defp resolve_page_parent_data_source(metadata, client, params, nil) do
    case Contracts.get(params, :page_id) do
      page_id when is_binary(page_id) ->
        with {:ok, page} <- NotionSDK.Pages.retrieve(client, %{"page_id" => page_id}) do
          resolve_page_parent_data_source(metadata, client, params, page)
        end

      _other ->
        {:ok, nil}
    end
  end

  defp resolve_page_parent_data_source(metadata, client, params, page) when is_map(page) do
    case parent_reference_from_page(page) do
      {:data_source, data_source_id} ->
        fetch_data_source_context(
          metadata,
          client,
          data_source_id,
          :page_parent_data_source,
          page_id_from_page(page, params),
          [:page, :data_source]
        )

      {:database, database_id} ->
        resolve_database_backed_page_parent(metadata, client, params, page, database_id)

      :none ->
        {:ok, nil}
    end
  end

  defp resolve_database_backed_page_parent(metadata, client, params, page, database_id) do
    with {:ok, database} <- NotionSDK.Databases.retrieve(client, %{"database_id" => database_id}),
         data_source_id when is_binary(data_source_id) <- database_data_source_id(database) do
      fetch_data_source_context(
        metadata,
        client,
        data_source_id,
        :page_parent_data_source,
        page_id_from_page(page, params),
        [:page, :database, :data_source]
      )
    else
      nil ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_direct_data_source(metadata, client, params) do
    case Contracts.get(params, :data_source_id) do
      data_source_id when is_binary(data_source_id) ->
        fetch_data_source_context(metadata, client, data_source_id, :data_source, nil, [
          :data_source
        ])

      _other ->
        {:ok, nil}
    end
  end

  defp fetch_data_source_context(
         metadata,
         client,
         data_source_id,
         context_source,
         source_page_id,
         resolved_via
       ) do
    with {:ok, data_source} <-
           NotionSDK.DataSources.retrieve(client, %{"data_source_id" => data_source_id}) do
      {:ok,
       SchemaContext.new!(
         context_source: context_source,
         data_source_id: data_source_id,
         source_page_id: source_page_id,
         properties: Contracts.get(data_source, :properties, %{}),
         resolved_via: resolved_via,
         slot_kinds: slot_kinds(metadata)
       )}
    end
  end

  defp has_surface_slots?(metadata, surface) do
    metadata
    |> Contracts.get(:schema_slots, [])
    |> Enum.any?(fn slot -> Contracts.get(slot, :surface) == surface end)
  end

  defp slot_kinds(metadata) do
    metadata
    |> Contracts.get(:schema_slots, [])
    |> Enum.map(&Contracts.get(&1, :kind))
    |> Enum.reject(&is_nil/1)
  end

  defp path_get(map, [segment | rest]) when is_map(map) do
    case Contracts.get(map, String.to_atom(segment)) do
      nil -> nil
      value when rest == [] -> value
      value when is_map(value) -> path_get(value, rest)
      _other -> nil
    end
  end

  defp path_get(_map, []), do: nil

  defp parent_reference_from_page(page) do
    parent = Contracts.get(page, :parent, %{})

    cond do
      is_binary(Contracts.get(parent, :data_source_id)) ->
        {:data_source, Contracts.get(parent, :data_source_id)}

      is_binary(Contracts.get(parent, :database_id)) ->
        {:database, Contracts.get(parent, :database_id)}

      true ->
        :none
    end
  end

  defp database_data_source_id(database) do
    database
    |> Contracts.get(:data_sources, [])
    |> Enum.map(&Contracts.get(&1, :id))
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
    |> case do
      [data_source_id] -> data_source_id
      _other -> nil
    end
  end

  defp page_id_from_page(page, params) do
    Contracts.get(page, :id) || Contracts.get(params, :page_id)
  end
end
