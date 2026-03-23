defmodule Jido.Integration.V2.Operator do
  @moduledoc """
  Shared read-only operator surface over durable auth and control-plane truth.

  This module packages durable discovery, compatibility, and review state
  without introducing a second store or cache.
  """

  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.TargetDescriptor

  @type connector_summary :: %{
          connector_id: String.t(),
          display_name: String.t(),
          description: String.t(),
          category: String.t(),
          tags: [String.t()],
          maturity: atom(),
          publication: atom(),
          auth_type: atom(),
          runtime_families: [atom()],
          capability_ids: [String.t()],
          capabilities: [capability_summary()]
        }

  @type capability_summary :: %{
          capability_id: String.t(),
          connector_id: String.t(),
          runtime_class: atom(),
          kind: atom(),
          transport_profile: atom(),
          name: String.t(),
          display_name: String.t(),
          description: String.t(),
          required_scopes: [String.t()],
          runtime: map(),
          consumer_surface: map()
        }

  @type compatible_target_match :: %{
          target: TargetDescriptor.t(),
          negotiated_versions: map(),
          capability: capability_summary(),
          connector: connector_summary()
        }

  @type review_packet :: %{
          run: Jido.Integration.V2.Run.t(),
          attempt: Jido.Integration.V2.Attempt.t() | nil,
          attempts: [Jido.Integration.V2.Attempt.t()],
          events: [Jido.Integration.V2.Event.t()],
          artifacts: [Jido.Integration.V2.ArtifactRef.t()],
          triggers: [Jido.Integration.V2.TriggerRecord.t()],
          target: TargetDescriptor.t() | nil,
          connection: Jido.Integration.V2.Auth.Connection.t() | nil,
          install: Jido.Integration.V2.Auth.Install.t() | nil,
          capability: capability_summary(),
          connector: connector_summary()
        }

  @spec catalog_entries() :: [connector_summary()]
  def catalog_entries do
    ControlPlane.connectors()
    |> Enum.map(&connector_summary/1)
  end

  @spec compatible_targets_for(String.t(), map()) ::
          {:ok, [compatible_target_match()]}
          | {:error, :unknown_capability | :unknown_connector}
  def compatible_targets_for(capability_id, requirements \\ %{}) when is_map(requirements) do
    with {:ok, capability} <- ControlPlane.fetch_capability(capability_id),
         {:ok, connector} <- ControlPlane.fetch_connector(capability.connector) do
      authored_requirements = TargetDescriptor.authored_requirements(capability, requirements)
      capability_summary = capability_summary(capability)
      connector_summary = connector_summary(connector)

      {:ok,
       Enum.map(ControlPlane.compatible_targets(authored_requirements), fn match ->
         Map.merge(match, %{capability: capability_summary, connector: connector_summary})
       end)}
    end
  end

  @spec review_packet(String.t(), map()) ::
          {:ok, review_packet()}
          | {:error, :unknown_run | :unknown_attempt | :unknown_capability | :unknown_connector}
  def review_packet(run_id, opts \\ %{}) when is_binary(run_id) and is_map(opts) do
    with {:ok, run} <- ControlPlane.fetch_run(run_id),
         {:ok, capability} <- ControlPlane.fetch_capability(run.capability_id),
         {:ok, connector} <- ControlPlane.fetch_connector(capability.connector),
         attempts = ControlPlane.attempts(run_id),
         {:ok, attempt} <- resolve_attempt(attempts, opts),
         {:ok, target} <- resolve_target(run, attempt),
         {:ok, connection} <- resolve_connection(run.credential_ref),
         {:ok, install} <- resolve_install(connection, run.credential_ref) do
      {:ok,
       %{
         run: run,
         attempt: attempt,
         attempts: attempts,
         events: ControlPlane.events(run_id),
         artifacts: ControlPlane.run_artifacts(run_id),
         triggers: ControlPlane.run_triggers(run_id),
         target: target,
         connection: connection,
         install: install,
         capability: capability_summary(capability),
         connector: connector_summary(connector)
       }}
    else
      :error -> {:error, :unknown_run}
      {:error, reason} -> {:error, reason}
    end
  end

  defp connector_summary(%Manifest{} = manifest) do
    %{
      connector_id: manifest.connector,
      display_name: manifest.catalog.display_name,
      description: manifest.catalog.description,
      category: manifest.catalog.category,
      tags: manifest.catalog.tags,
      maturity: manifest.catalog.maturity,
      publication: manifest.catalog.publication,
      auth_type: manifest.auth.auth_type,
      runtime_families: manifest.runtime_families,
      capability_ids: Enum.map(manifest.capabilities, & &1.id),
      capabilities: Enum.map(manifest.capabilities, &capability_summary/1)
    }
  end

  defp capability_summary(%Capability{} = capability) do
    %{
      capability_id: capability.id,
      connector_id: capability.connector,
      runtime_class: capability.runtime_class,
      kind: capability.kind,
      transport_profile: capability.transport_profile,
      name: Map.fetch!(capability.metadata, :name),
      display_name: Map.fetch!(capability.metadata, :display_name),
      description: Map.fetch!(capability.metadata, :description),
      required_scopes: Capability.required_scopes(capability),
      runtime: Map.get(capability.metadata, :runtime, %{}),
      consumer_surface: Map.get(capability.metadata, :consumer_surface, %{})
    }
  end

  defp resolve_attempt([], %{}), do: {:ok, nil}
  defp resolve_attempt(attempts, %{attempt_id: nil}), do: {:ok, List.last(attempts)}

  defp resolve_attempt(attempts, %{attempt_id: attempt_id}) do
    case Enum.find(attempts, &(&1.attempt_id == attempt_id)) do
      nil -> {:error, :unknown_attempt}
      attempt -> {:ok, attempt}
    end
  end

  defp resolve_attempt(attempts, %{}), do: {:ok, List.last(attempts)}

  defp resolve_target(run, nil), do: fetch_optional_target(run.target_id)

  defp resolve_target(run, attempt) do
    attempt.target_id
    |> case do
      nil -> run.target_id
      target_id -> target_id
    end
    |> fetch_optional_target()
  end

  defp fetch_optional_target(nil), do: {:ok, nil}

  defp fetch_optional_target(target_id) do
    case ControlPlane.fetch_target(target_id) do
      {:ok, target} -> {:ok, target}
      :error -> {:ok, nil}
    end
  end

  defp resolve_connection(%CredentialRef{metadata: metadata}) do
    case Map.get(metadata, :connection_id) do
      nil ->
        {:ok, nil}

      connection_id ->
        case Auth.connection_status(connection_id) do
          {:ok, connection} -> {:ok, connection}
          {:error, :unknown_connection} -> {:ok, nil}
        end
    end
  end

  defp resolve_install(nil, %CredentialRef{metadata: metadata}) do
    metadata
    |> Map.get(:install_id)
    |> fetch_optional_install()
  end

  defp resolve_install(connection, _credential_ref) do
    fetch_optional_install(connection.install_id)
  end

  defp fetch_optional_install(nil), do: {:ok, nil}

  defp fetch_optional_install(install_id) do
    case Auth.fetch_install(install_id) do
      {:ok, install} -> {:ok, install}
      {:error, :unknown_install} -> {:ok, nil}
    end
  end
end
