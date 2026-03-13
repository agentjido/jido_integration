defmodule Jido.Integration.Auth.Store.ETS do
  @moduledoc """
  ETS-backed credential store for development and testing.

  Stores credentials in a private ETS table keyed by auth_ref.
  Supports scope enforcement (connector_id must match auth_ref prefix)
  and TTL expiry (expired credentials return `{:error, :expired}`).

  ## Auth Ref Format

      "auth:<connector_type>:<scope_id>"

  The connector_type segment is used for scope enforcement and listing.
  """

  use GenServer

  alias Jido.Integration.Auth.Credential

  @behaviour Jido.Integration.Auth.Store

  @impl true
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} ->
        GenServer.start_link(__MODULE__, opts)

      {:ok, name} ->
        GenServer.start_link(__MODULE__, opts, name: name)

      :error ->
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
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

  # Server

  @impl GenServer
  def init(_opts) do
    table = :ets.new(:auth_store, [:set, :private])
    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_call({:store, auth_ref, credential}, _from, state) do
    :ets.insert(state.table, {auth_ref, credential})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:fetch, auth_ref, opts}, _from, state) do
    result =
      case :ets.lookup(state.table, auth_ref) do
        [{^auth_ref, credential}] ->
          with :ok <- check_scope(auth_ref, opts),
               :ok <- check_expiry(credential, opts) do
            {:ok, credential}
          end

        [] ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:delete, auth_ref}, _from, state) do
    case :ets.lookup(state.table, auth_ref) do
      [{^auth_ref, _}] ->
        :ets.delete(state.table, auth_ref)
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:list, connector_type}, _from, state) do
    prefix = "auth:#{connector_type}:"

    entries =
      :ets.tab2list(state.table)
      |> Enum.filter(fn {ref, _cred} -> String.starts_with?(ref, prefix) end)

    {:reply, entries, state}
  end

  # Scope enforcement: connector_id in context must match auth_ref's connector segment

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

  defp check_expiry(%Credential{} = cred) do
    if Credential.expired?(cred) do
      {:error, :expired}
    else
      :ok
    end
  end

  defp check_expiry(%Credential{} = cred, opts) do
    if Keyword.get(opts, :allow_expired, false) do
      :ok
    else
      check_expiry(cred)
    end
  end

  defp parse_connector_type("auth:" <> rest) do
    rest |> String.split(":", parts: 2) |> List.first()
  end

  defp parse_connector_type(_), do: nil
end
