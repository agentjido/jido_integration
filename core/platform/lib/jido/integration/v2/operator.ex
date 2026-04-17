defmodule Jido.Integration.V2.Operator do
  @moduledoc """
  Shared operator surface over durable auth and control-plane truth.

  This module packages durable discovery, compatibility, and review state
  without introducing a second store or cache.
  """

  alias Jido.Integration.V2.AttachGrant
  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.BoundarySession
  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.ControlPlane.InferenceRecorder
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.DerivedStateAttachment
  alias Jido.Integration.V2.EvidenceRef
  alias Jido.Integration.V2.GovernanceRef
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.ProjectedCatalog
  alias Jido.Integration.V2.ReviewProjection
  alias Jido.Integration.V2.SubjectRef
  alias Jido.Integration.V2.TargetDescriptor

  @normalized_atom_keys %{
    "accepted" => :accepted,
    "allocated" => :allocated,
    "attached" => :attached,
    "attaching" => :attaching,
    "closed" => :closed,
    "expired" => :expired,
    "issued" => :issued,
    "revoked" => :revoked,
    "stale" => :stale
  }

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
          metadata: ReviewProjection.dump_t(),
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

  @type attachment_context :: %{
          run: Jido.Integration.V2.Run.t(),
          attempt: Jido.Integration.V2.Attempt.t() | nil,
          attempts: [Jido.Integration.V2.Attempt.t()],
          events: [Jido.Integration.V2.Event.t()],
          artifacts: [Jido.Integration.V2.ArtifactRef.t()],
          triggers: [Jido.Integration.V2.TriggerRecord.t()],
          target: TargetDescriptor.t() | nil,
          connection: Jido.Integration.V2.Auth.Connection.t() | nil,
          install: Jido.Integration.V2.Auth.Install.t() | nil
        }

  @type boundary_session_projection :: BoundarySession.t()
  @type attach_grant_projection :: AttachGrant.t()

  @spec catalog_entries() :: [connector_summary()]
  def catalog_entries do
    ControlPlane.connectors()
    |> Enum.map(&connector_summary/1)
  end

  @spec runs(map()) :: [Jido.Integration.V2.Run.t()]
  def runs(filters \\ %{}) when is_map(filters) do
    ControlPlane.runs(%{})
    |> Enum.sort_by(&record_sort_key(&1, :run_id))
    |> filter_records(filters)
  end

  @spec projected_catalog_entries() :: [projected_connector_summary()]
  def projected_catalog_entries do
    ControlPlane.connectors()
    |> Enum.map(&ProjectedCatalog.connector_entry/1)
  end

  @spec boundary_sessions(map()) :: [boundary_session_projection()]
  def boundary_sessions(filters \\ %{}) when is_map(filters) do
    ControlPlane.runs(%{})
    |> Enum.flat_map(&boundary_sessions_for_run/1)
    |> Enum.sort_by(&record_sort_key(&1, :boundary_session_id))
    |> filter_records(filters)
  end

  @spec fetch_boundary_session(String.t()) :: {:ok, BoundarySession.t()} | :error
  def fetch_boundary_session(boundary_session_id) when is_binary(boundary_session_id) do
    case Enum.find(boundary_sessions(%{}), &(&1.boundary_session_id == boundary_session_id)) do
      %BoundarySession{} = boundary_session -> {:ok, boundary_session}
      nil -> :error
    end
  end

  @spec attach_grants(map()) :: [attach_grant_projection()]
  def attach_grants(filters \\ %{}) when is_map(filters) do
    ControlPlane.runs(%{})
    |> Enum.flat_map(&attach_grants_for_run/1)
    |> Enum.sort_by(&record_sort_key(&1, :attach_grant_id))
    |> filter_records(filters)
  end

  @spec fetch_attach_grant(String.t()) :: {:ok, AttachGrant.t()} | :error
  def fetch_attach_grant(attach_grant_id) when is_binary(attach_grant_id) do
    case Enum.find(attach_grants(%{}), &(&1.attach_grant_id == attach_grant_id)) do
      %AttachGrant{} = attach_grant -> {:ok, attach_grant}
      nil -> :error
    end
  end

  @spec issue_attach_grant(String.t(), map()) ::
          {:ok, AttachGrant.t()}
          | {:error, :unknown_run | :unknown_attempt | :boundary_session_unavailable}
  def issue_attach_grant(run_id, opts \\ %{}) when is_binary(run_id) and is_map(opts) do
    case attachment_context(run_id, opts) do
      {:ok, %{run: run, attempt: attempt}} ->
        case attach_grant_projection(run, attempt) do
          %AttachGrant{} = attach_grant -> {:ok, attach_grant}
          nil -> {:error, :boundary_session_unavailable}
        end

      :error ->
        {:error, :unknown_run}

      {:error, reason} ->
        {:error, reason}
    end
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
    with {:ok, context} <- attachment_context(run_id, opts),
         {:ok, catalog} <- resolve_review_catalog(context.run, context.attempt) do
      review_connection = review_safe_connection(context.connection)
      review_install = review_safe_install(context.install)

      {:ok,
       %{
         metadata:
           build_review_packet_metadata(
             context.run,
             context.attempt,
             %{
               attempts: context.attempts,
               events: context.events,
               artifacts: context.artifacts,
               triggers: context.triggers,
               target: context.target,
               connection: review_connection,
               install: review_install
             },
             opts
           ),
         run: context.run,
         attempt: context.attempt,
         attempts: context.attempts,
         events: context.events,
         artifacts: context.artifacts,
         triggers: context.triggers,
         target: context.target,
         connection: review_connection,
         install: review_install,
         capability: capability_summary(catalog.capability),
         connector: connector_summary(catalog.connector)
       }}
    else
      :error -> {:error, :unknown_run}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec derived_state_attachment(String.t(), map()) ::
          {:ok, DerivedStateAttachment.t()} | {:error, :unknown_run | :unknown_attempt}
  def derived_state_attachment(run_id, opts \\ %{}) when is_binary(run_id) and is_map(opts) do
    case attachment_context(run_id, opts) do
      {:ok, context} ->
        {:ok, build_derived_state_attachment(context.run, context.attempt, context, opts)}

      :error ->
        {:error, :unknown_run}

      {:error, reason} ->
        {:error, reason}
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

  defp connector_summary(%{} = summary), do: summary

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

  defp capability_summary(%{} = summary), do: summary

  defp resolve_review_catalog(run, attempt) do
    case InferenceRecorder.inference_review_summary(run, attempt) do
      {:ok, catalog} ->
        {:ok, catalog}

      :error ->
        with {:ok, capability} <- ControlPlane.fetch_capability(run.capability_id),
             {:ok, connector} <- ControlPlane.fetch_connector(capability.connector) do
          {:ok, %{capability: capability, connector: connector}}
        end
    end
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

  defp review_safe_connection(nil), do: nil
  defp review_safe_connection(connection), do: connection

  defp review_safe_install(nil), do: nil
  defp review_safe_install(install), do: Auth.Install.review_safe(install)

  defp attachment_context(run_id, opts) do
    with {:ok, run} <- ControlPlane.fetch_run(run_id),
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
         run: run,
         attempt: attempt,
         attempts: attempts,
         events: events,
         artifacts: artifacts,
         triggers: triggers,
         target: target,
         connection: connection,
         install: install
       }}
    else
      :error -> :error
      {:error, reason} -> {:error, reason}
    end
  end

  defp boundary_sessions_for_run(run) do
    run.run_id
    |> ControlPlane.attempts()
    |> Enum.map(&boundary_session_projection(run, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp attach_grants_for_run(run) do
    run.run_id
    |> ControlPlane.attempts()
    |> Enum.map(&attach_grant_projection(run, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp boundary_session_projection(_run, nil), do: nil

  defp boundary_session_projection(run, attempt) do
    case fetch_boundary_metadata(attempt) do
      %{descriptor: descriptor, route: route, attach_grant: attach_grant} ->
        build_boundary_session(run, attempt, descriptor, route, attach_grant)

      nil ->
        nil
    end
  end

  defp attach_grant_projection(_run, nil), do: nil

  defp attach_grant_projection(run, attempt) do
    with %BoundarySession{} = boundary_session <- boundary_session_projection(run, attempt),
         %{attach_grant: attach_grant, descriptor: descriptor, route: route} <-
           fetch_boundary_metadata(attempt) do
      build_attach_grant(boundary_session, run, attempt, descriptor, route, attach_grant)
    else
      _other -> nil
    end
  end

  defp build_boundary_session(run, attempt, descriptor, route, attach_grant) do
    boundary_session_id =
      map_get(descriptor, :boundary_session_id) ||
        map_get(descriptor, :session_id) ||
        attempt.runtime_ref_id

    if is_binary(boundary_session_id) and boundary_session_id != "" do
      BoundarySession.new!(%{
        boundary_session_id: boundary_session_id,
        session_id: map_get(descriptor, :session_id, boundary_session_id),
        tenant_id: tenant_id(run),
        target_id: attempt.target_id || run.target_id,
        route_id: map_get(route, :route_id),
        attach_grant_id: attach_grant_id(boundary_session_id, attempt, attach_grant),
        status: boundary_session_status(descriptor, attach_grant),
        inserted_at: attempt.inserted_at,
        updated_at: attempt.updated_at,
        metadata: %{
          "run_id" => run.run_id,
          "attempt_id" => attempt.attempt_id,
          "runtime_ref_id" => attempt.runtime_ref_id,
          "boundary_descriptor" => descriptor,
          "route" => route,
          "attach_grant" => attach_grant
        }
      })
    end
  end

  defp build_attach_grant(boundary_session, run, attempt, descriptor, route, attach_grant) do
    AttachGrant.new!(%{
      attach_grant_id:
        map_get(attach_grant, :attach_grant_id) ||
          attach_grant_id(boundary_session.boundary_session_id, attempt, attach_grant),
      boundary_session_id: boundary_session.boundary_session_id,
      route_id: map_get(route, :route_id),
      subject_id: map_get(attach_grant, :subject_id, run.run_id),
      status: attach_grant_status(attach_grant),
      lease_expires_at: map_get(attach_grant, :lease_expires_at),
      inserted_at: attempt.inserted_at,
      updated_at: attempt.updated_at,
      metadata: %{
        "run_id" => run.run_id,
        "attempt_id" => attempt.attempt_id,
        "runtime_ref_id" => attempt.runtime_ref_id,
        "attach_mode" => map_get(attach_grant, :attach_mode),
        "boundary_descriptor" => descriptor,
        "route" => route
      }
    })
  end

  defp fetch_boundary_metadata(attempt) do
    boundary =
      attempt.output
      |> map_get(:metadata, %{})
      |> map_get(:boundary)

    case boundary do
      %{} = boundary_map ->
        %{
          descriptor: normalize_metadata_map(map_get(boundary_map, :descriptor, %{})),
          route: normalize_metadata_map(map_get(boundary_map, :route, %{})),
          attach_grant: normalize_metadata_map(map_get(boundary_map, :attach_grant, %{}))
        }

      _other ->
        nil
    end
  end

  defp attach_grant_id(boundary_session_id, attempt, attach_grant) do
    map_get(attach_grant, :attach_grant_id) ||
      "attach_grant:#{boundary_session_id}:#{attempt.attempt_id}"
  end

  defp tenant_id(run) do
    run.credential_ref.metadata
    |> map_get(:tenant_id)
  end

  defp boundary_session_status(descriptor, attach_grant) do
    descriptor
    |> map_get(:session_status, map_get(descriptor, :status))
    |> normalize_boundary_session_status(attach_grant)
  end

  defp normalize_boundary_session_status(nil, attach_grant) do
    case attach_grant_status(attach_grant) do
      :accepted -> :attached
      :revoked -> :closed
      :expired -> :stale
      _other -> :allocated
    end
  end

  defp normalize_boundary_session_status(value, _attach_grant) do
    case normalize_atom_key(value) do
      :allocated -> :allocated
      :attaching -> :attaching
      :attached -> :attached
      :stale -> :stale
      :closed -> :closed
      _other -> :allocated
    end
  end

  defp attach_grant_status(attach_grant) do
    case normalize_atom_key(map_get(attach_grant, :status)) do
      :issued -> :issued
      :accepted -> :accepted
      :revoked -> :revoked
      :expired -> :expired
      _other -> :issued
    end
  end

  defp filter_records(records, filters) when is_map(filters) do
    Enum.filter(records, fn record ->
      Enum.all?(filters, fn {key, value} ->
        actual =
          map_get(
            record,
            key,
            map_get(
              map_get(record, :metadata, %{}),
              key,
              map_get(map_get(record, :credential_ref, %{}), :metadata, %{}) |> map_get(key)
            )
          )

        comparable_value(actual) == comparable_value(value)
      end)
    end)
  end

  defp record_sort_key(record, id_key) do
    {sort_timestamp(map_get(record, :inserted_at)), comparable_value(map_get(record, id_key, ""))}
  end

  defp sort_timestamp(%DateTime{} = timestamp), do: DateTime.to_unix(timestamp, :microsecond)
  defp sort_timestamp(_other), do: 0

  defp comparable_value(value) when is_atom(value), do: Atom.to_string(value)
  defp comparable_value(value), do: value

  defp normalize_metadata_map(%{} = value), do: value
  defp normalize_metadata_map(_other), do: %{}

  defp map_get(map, key, default \\ nil)
  defp map_get(nil, _key, default), do: default

  defp map_get(map, key, default) when is_map(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp normalize_atom_key(value) when is_atom(value), do: value

  defp normalize_atom_key(value) when is_binary(value) do
    normalized_key =
      value
      |> String.downcase()
      |> String.replace("-", "_")

    Map.get(@normalized_atom_keys, normalized_key, normalized_key)
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

    ReviewProjection.new!(%{
      schema_version: Contracts.schema_version(),
      projection: "operator.review_packet",
      packet_ref: packet_ref,
      subject: subject_ref,
      selected_attempt: selected_attempt_subject_ref(attempt),
      evidence_refs: evidence_refs,
      governance_refs: build_governance_refs(run, events, subject_ref, evidence_refs)
    })
    |> ReviewProjection.dump()
  end

  defp build_derived_state_attachment(
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
    attachment_ref = Contracts.derived_state_attachment_ref(run.run_id, requested_attempt_id)

    evidence_refs =
      [
        build_evidence_ref(:run, run.run_id, attachment_ref, subject_ref, %{status: run.status}),
        build_attempt_evidence_refs(attempts, attachment_ref, subject_ref),
        build_event_evidence_refs(events, attachment_ref, subject_ref),
        build_artifact_evidence_refs(artifacts, attachment_ref, subject_ref),
        build_trigger_evidence_refs(triggers, attachment_ref, subject_ref),
        build_optional_evidence_ref(
          target,
          :target,
          :target_id,
          attachment_ref,
          subject_ref,
          fn target ->
            %{capability_id: target.capability_id, runtime_class: target.runtime_class}
          end
        ),
        build_optional_evidence_ref(
          connection,
          :connection,
          :connection_id,
          attachment_ref,
          subject_ref,
          fn connection ->
            %{connector_id: connection.connector_id, state: connection.state}
          end
        ),
        build_optional_evidence_ref(
          install,
          :install,
          :install_id,
          attachment_ref,
          subject_ref,
          fn install ->
            %{connection_id: install.connection_id, state: install.state}
          end
        )
      ]
      |> List.flatten()

    DerivedStateAttachment.new!(%{
      subject: subject_ref,
      evidence_refs: evidence_refs,
      governance_refs: build_governance_refs(run, events, subject_ref, evidence_refs),
      metadata: %{
        attachment_ref: attachment_ref,
        source_projection: "operator.derived_state_attachment",
        selected_attempt:
          case selected_attempt_subject_ref(attempt) do
            nil -> nil
            subject_ref -> SubjectRef.dump(subject_ref)
          end
      }
    })
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

  defp selected_attempt_subject_ref(nil), do: nil

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
    end)
  end

  defp governance_event?(%Jido.Integration.V2.Event{type: "audit.policy_denied"}), do: true
  defp governance_event?(%Jido.Integration.V2.Event{type: "audit.policy_shed"}), do: true
  defp governance_event?(%Jido.Integration.V2.Event{}), do: false

  defp governance_status(status) when status in [:denied, :shed], do: status
  defp governance_status(_status), do: :policy_decision
end
