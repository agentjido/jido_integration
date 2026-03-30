defmodule Jido.Integration.V2.Operator do
  @moduledoc """
  Shared read-only operator surface over durable auth and control-plane truth.

  This module packages durable discovery, compatibility, and review state
  without introducing a second store or cache.
  """

  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.ProjectedCatalog
  alias Jido.Integration.V2.SubjectRef
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

  @type projected_connector_summary :: %{
          connector_id: String.t(),
          display_name: String.t(),
          description: String.t(),
          category: String.t(),
          tags: [String.t()],
          docs_refs: [String.t()],
          maturity: atom(),
          publication: atom(),
          generated_plugin: %{
            module: module(),
            name: String.t(),
            state_key: atom()
          },
          generated_action_names: [String.t()],
          generated_sensor_names: [String.t()],
          common_projected_operations: [map()],
          common_projected_triggers: [map()]
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
          metadata: %{
            schema_version: String.t(),
            projection: String.t(),
            packet_ref: String.t(),
            subject: map(),
            selected_attempt: map() | nil,
            evidence_refs: [map()],
            governance_refs: [map()]
          },
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

  @spec projected_catalog_entries() :: [projected_connector_summary()]
  def projected_catalog_entries do
    ControlPlane.connectors()
    |> Enum.map(&ProjectedCatalog.connector_entry/1)
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
         events = ControlPlane.events(run_id),
         artifacts = ControlPlane.run_artifacts(run_id),
         triggers = ControlPlane.run_triggers(run_id),
         {:ok, target} <- resolve_target(run, attempt),
         {:ok, connection} <- resolve_connection(run.credential_ref),
         {:ok, install} <- resolve_install(connection, run.credential_ref) do
      {:ok,
       %{
         metadata:
           build_review_packet_metadata(
             run,
             attempt,
             %{
               attempts: attempts,
               events: events,
               artifacts: artifacts,
               triggers: triggers,
               target: target,
               connection: connection,
               install: install
             },
             opts
           ),
         run: run,
         attempt: attempt,
         attempts: attempts,
         events: events,
         artifacts: artifacts,
         triggers: triggers,
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

  defp build_review_packet_metadata(
         run,
         attempt,
         %{
           attempts: attempts,
           events: events,
           artifacts: artifacts,
           triggers: triggers,
           target: target,
           connection: connection,
           install: install
         },
         opts
       ) do
    subject_ref = SubjectRef.new!(%{kind: :run, id: run.run_id})
    requested_attempt_id = Map.get(opts, :attempt_id)
    packet_ref = Contracts.review_packet_ref(run.run_id, requested_attempt_id)

    evidence_refs =
      [
        build_evidence_ref(:run, run.run_id, packet_ref, subject_ref, %{status: run.status}),
        build_attempt_evidence_refs(attempts, packet_ref, subject_ref),
        build_event_evidence_refs(events, packet_ref, subject_ref),
        build_artifact_evidence_refs(artifacts, packet_ref, subject_ref),
        build_trigger_evidence_refs(triggers, packet_ref, subject_ref),
        build_optional_evidence_ref(
          target,
          :target,
          :target_id,
          packet_ref,
          subject_ref,
          fn target ->
            %{capability_id: target.capability_id, runtime_class: target.runtime_class}
          end
        ),
        build_optional_evidence_ref(
          connection,
          :connection,
          :connection_id,
          packet_ref,
          subject_ref,
          fn connection ->
            %{connector_id: connection.connector_id, state: connection.state}
          end
        ),
        build_optional_evidence_ref(
          install,
          :install,
          :install_id,
          packet_ref,
          subject_ref,
          fn install ->
            %{connection_id: install.connection_id, state: install.state}
          end
        )
      ]
      |> List.flatten()

    %{
      schema_version: Contracts.schema_version(),
      projection: "operator.review_packet",
      packet_ref: packet_ref,
      subject: SubjectRef.dump(subject_ref),
      selected_attempt: maybe_dump_selected_attempt(attempt),
      evidence_refs: Enum.map(evidence_refs, &EvidenceRef.dump/1),
      governance_refs: build_governance_refs(run, events, subject_ref, evidence_refs)
    }
  end

  defp build_attempt_evidence_refs(attempts, packet_ref, subject_ref) do
    Enum.map(attempts, fn attempt ->
      build_evidence_ref(:attempt, attempt.attempt_id, packet_ref, subject_ref, %{
        attempt: attempt.attempt,
        run_id: attempt.run_id,
        status: attempt.status
      })
    end)
  end

  defp build_event_evidence_refs(events, packet_ref, subject_ref) do
    Enum.map(events, fn event ->
      build_evidence_ref(:event, event.event_id, packet_ref, subject_ref, %{
        attempt_id: event.attempt_id,
        type: event.type
      })
    end)
  end

  defp build_artifact_evidence_refs(artifacts, packet_ref, subject_ref) do
    Enum.map(artifacts, fn artifact ->
      build_evidence_ref(:artifact, artifact.artifact_id, packet_ref, subject_ref, %{
        attempt_id: artifact.attempt_id,
        artifact_type: artifact.artifact_type
      })
    end)
  end

  defp build_trigger_evidence_refs(triggers, packet_ref, subject_ref) do
    Enum.map(triggers, fn trigger ->
      build_evidence_ref(:trigger, trigger.admission_id, packet_ref, subject_ref, %{
        trigger_id: trigger.trigger_id,
        source: trigger.source,
        status: trigger.status
      })
    end)
  end

  defp build_optional_evidence_ref(
         nil,
         _kind,
         _id_field,
         _packet_ref,
         _subject_ref,
         _metadata_fun
       ),
       do: []

  defp build_optional_evidence_ref(record, kind, id_field, packet_ref, subject_ref, metadata_fun) do
    build_evidence_ref(
      kind,
      Map.fetch!(record, id_field),
      packet_ref,
      subject_ref,
      metadata_fun.(record)
    )
  end

  defp build_evidence_ref(kind, id, packet_ref, subject_ref, metadata) do
    EvidenceRef.new!(%{
      kind: kind,
      id: id,
      packet_ref: packet_ref,
      subject: subject_ref,
      metadata: metadata
    })
  end

  defp maybe_dump_selected_attempt(nil), do: nil

  defp maybe_dump_selected_attempt(attempt) do
    attempt
    |> selected_attempt_subject_ref()
    |> SubjectRef.dump()
  end

  defp selected_attempt_subject_ref(attempt) do
    SubjectRef.new!(%{
      kind: :attempt,
      id: attempt.attempt_id,
      metadata: %{attempt: attempt.attempt, run_id: attempt.run_id}
    })
  end

  defp build_governance_refs(run, events, subject_ref, evidence_refs) do
    run_evidence = Enum.find(evidence_refs, &(&1.kind == :run and &1.id == run.run_id))

    events
    |> Enum.filter(&governance_event?/1)
    |> Enum.map(fn event ->
      audit_evidence = Enum.find(evidence_refs, &(&1.kind == :event and &1.id == event.event_id))

      GovernanceRef.new!(%{
        kind: :policy_decision,
        id: event.event_id,
        subject: subject_ref,
        evidence: Enum.reject([run_evidence, audit_evidence], &is_nil/1),
        metadata: %{status: governance_status(run.status), event_type: event.type}
      })
      |> GovernanceRef.dump()
    end)
  end

  defp governance_event?(%Jido.Integration.V2.Event{type: "audit.policy_denied"}), do: true
  defp governance_event?(%Jido.Integration.V2.Event{type: "audit.policy_shed"}), do: true
  defp governance_event?(%Jido.Integration.V2.Event{}), do: false

  defp governance_status(status) when status in [:denied, :shed], do: status
  defp governance_status(_status), do: :policy_decision
end
