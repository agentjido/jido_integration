defmodule Jido.Integration.Auth.Store.Disk do
  @moduledoc """
  File-backed credential store for durable local runtime state.
  """

  use GenServer

  alias Jido.Integration.Auth.Credential
  alias Jido.Integration.Runtime.Persistence

  @behaviour Jido.Integration.Auth.Store

  @impl true
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} -> GenServer.start_link(__MODULE__, opts)
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @impl Jido.Integration.Auth.Store
  def store(server, auth_ref, %Credential{} = credential) do
    GenServer.call(server, {:store, auth_ref, credential})
  end

  @impl Jido.Integration.Auth.Store
  def fetch(server, auth_ref, opts \\ []) do
    GenServer.call(server, {:fetch, auth_ref, opts})
  end

  @impl Jido.Integration.Auth.Store
  def delete(server, auth_ref) do
    GenServer.call(server, {:delete, auth_ref})
  end

  @impl Jido.Integration.Auth.Store
  def list(server, connector_type) do
    GenServer.call(server, {:list, connector_type})
  end

  @impl GenServer
  def init(opts) do
    path = Persistence.default_path("credentials", opts)
    {:ok, %{path: path, entries: Persistence.load(path, %{})}}
  end

  @impl GenServer
  def handle_call({:store, auth_ref, credential}, _from, state) do
    entries = Map.put(state.entries, auth_ref, credential)
    :ok = Persistence.persist(state.path, entries)
    {:reply, :ok, %{state | entries: entries}}
  end

  @impl GenServer
  def handle_call({:fetch, auth_ref, opts}, _from, state) do
    result =
      case Map.get(state.entries, auth_ref) do
        %Credential{} = credential ->
          with :ok <- check_scope(auth_ref, opts),
               :ok <- check_expiry(credential, opts) do
            {:ok, credential}
          end

        nil ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:delete, auth_ref}, _from, state) do
    if Map.has_key?(state.entries, auth_ref) do
      entries = Map.delete(state.entries, auth_ref)
      :ok = Persistence.persist(state.path, entries)
      {:reply, :ok, %{state | entries: entries}}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:list, connector_type}, _from, state) do
    prefix = "auth:#{connector_type}:"

    entries =
      state.entries
      |> Enum.filter(fn {ref, _cred} -> String.starts_with?(ref, prefix) end)

    {:reply, entries, state}
  end

  defp check_scope(auth_ref, opts) do
    case Keyword.get(opts, :connector_id) do
      nil ->
        :ok

      connector_id ->
        case parse_connector_type(auth_ref) do
          ^connector_id -> :ok
          _ -> {:error, :scope_violation}
        end
    end
  end

  defp check_expiry(%Credential{} = cred, opts) do
    if Keyword.get(opts, :allow_expired, false) or not Credential.expired?(cred) do
      :ok
    else
      {:error, :expired}
    end
  end

  defp parse_connector_type("auth:" <> rest) do
    rest |> String.split(":", parts: 2) |> List.first()
  end

  defp parse_connector_type(_), do: nil
end
