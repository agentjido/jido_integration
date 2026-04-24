defmodule Jido.Integration.V2.StoreLocal.State do
  @moduledoc false

  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.Auth.Connection
  alias Jido.Integration.V2.Auth.Install
  alias Jido.Integration.V2.Auth.LeaseRecord
  alias Jido.Integration.V2.Auth.SecretEnvelope
  alias Jido.Integration.V2.BrainIngress.SubmissionDedupe
  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Credential
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.Redaction
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.ServiceSimulationProfile
  alias Jido.Integration.V2.SimulationProfileRegistryEntry
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.SubmissionIdentity
  alias Jido.Integration.V2.SubmissionRejection
  alias Jido.Integration.V2.TargetDescriptor
  alias Jido.Integration.V2.TriggerCheckpoint
  alias Jido.Integration.V2.TriggerRecord

  @type event_entry :: %{event: Event.t(), inserted_at: DateTime.t()}
  @type persisted_credential :: %{
          id: String.t(),
          credential_ref_id: String.t(),
          connection_id: String.t() | nil,
          profile_id: String.t() | nil,
          subject: String.t(),
          auth_type: atom(),
          version: pos_integer(),
          scopes: [String.t()],
          lease_fields: [String.t()],
          secret_envelope: map(),
          expires_at: DateTime.t() | nil,
          refresh_token_expires_at: DateTime.t() | nil,
          source: atom() | nil,
          source_ref: map() | nil,
          supersedes_credential_id: String.t() | nil,
          revoked_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct credentials: %{},
            connections: %{},
            installs: %{},
            leases: %{},
            runs: %{},
            attempts: %{},
            events: %{},
            artifacts: %{},
            targets: %{},
            triggers: %{},
            checkpoints: %{},
            dedupe: %{},
            submissions: %{},
            expired_submissions: %{},
            submission_acceptances: %{},
            submission_rejections: %{},
            profile_registry_entries: %{}

  @type t :: %__MODULE__{
          credentials: %{optional(String.t()) => persisted_credential()},
          connections: %{optional(String.t()) => Connection.t()},
          installs: %{optional(String.t()) => Install.t()},
          leases: %{optional(String.t()) => LeaseRecord.t()},
          runs: %{optional(String.t()) => Run.t()},
          attempts: %{optional(String.t()) => Attempt.t()},
          events: %{optional(String.t()) => [event_entry()]},
          artifacts: %{optional(String.t()) => ArtifactRef.t()},
          targets: %{optional(String.t()) => TargetDescriptor.t()},
          triggers: %{
            optional({String.t(), String.t(), String.t(), String.t()}) => TriggerRecord.t()
          },
          checkpoints: %{
            optional({String.t(), String.t(), String.t(), String.t()}) => TriggerCheckpoint.t()
          },
          dedupe: %{optional({String.t(), String.t(), String.t(), String.t()}) => DateTime.t()},
          submissions: %{
            optional({String.t(), String.t()}) => %{
              submission_key: String.t(),
              identity_checksum: String.t(),
              acceptance: SubmissionAcceptance.t() | nil,
              rejection: SubmissionRejection.t() | nil,
              last_seen_at: DateTime.t(),
              expires_at: DateTime.t()
            }
          },
          expired_submissions: %{
            optional({String.t(), String.t()}) => %{
              submission_key: String.t(),
              status: :accepted | :rejected,
              last_seen_at: DateTime.t()
            }
          },
          submission_acceptances: %{optional(String.t()) => SubmissionAcceptance.t()},
          submission_rejections: %{optional(String.t()) => SubmissionRejection.t()},
          profile_registry_entries: %{
            optional(String.t()) => SimulationProfileRegistryEntry.t()
          }
        }

  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @spec reset_credentials(t()) :: {:ok, t()}
  def reset_credentials(%__MODULE__{} = state), do: {:ok, %{state | credentials: %{}}}

  @spec reset_connections(t()) :: {:ok, t()}
  def reset_connections(%__MODULE__{} = state), do: {:ok, %{state | connections: %{}}}

  @spec reset_installs(t()) :: {:ok, t()}
  def reset_installs(%__MODULE__{} = state), do: {:ok, %{state | installs: %{}}}

  @spec reset_leases(t()) :: {:ok, t()}
  def reset_leases(%__MODULE__{} = state), do: {:ok, %{state | leases: %{}}}

  @spec reset_runs(t()) :: {:ok, t()}
  def reset_runs(%__MODULE__{} = state) do
    {:ok, %{state | runs: %{}, attempts: %{}, events: %{}}}
  end

  @spec reset_attempts(t()) :: {:ok, t()}
  def reset_attempts(%__MODULE__{} = state), do: {:ok, %{state | attempts: %{}}}

  @spec reset_events(t()) :: {:ok, t()}
  def reset_events(%__MODULE__{} = state), do: {:ok, %{state | events: %{}}}

  @spec reset_artifacts(t()) :: {:ok, t()}
  def reset_artifacts(%__MODULE__{} = state), do: {:ok, %{state | artifacts: %{}}}

  @spec reset_targets(t()) :: {:ok, t()}
  def reset_targets(%__MODULE__{} = state), do: {:ok, %{state | targets: %{}}}

  @spec reset_ingress(t()) :: {:ok, t()}
  def reset_ingress(%__MODULE__{} = state) do
    {:ok, %{state | triggers: %{}, checkpoints: %{}, dedupe: %{}}}
  end

  @spec reset_submission_ledger(t()) :: {:ok, t()}
  def reset_submission_ledger(%__MODULE__{} = state) do
    {:ok,
     %{
       state
       | submissions: %{},
         expired_submissions: %{},
         submission_acceptances: %{},
         submission_rejections: %{}
     }}
  end

  @spec reset_profile_registry(t()) :: {:ok, t()}
  def reset_profile_registry(%__MODULE__{} = state) do
    {:ok, %{state | profile_registry_entries: %{}}}
  end

  @spec store_credential(t(), Credential.t()) :: {:ok, t()}
  def store_credential(%__MODULE__{} = state, %Credential{} = credential) do
    persisted = %{
      id: credential.id,
      credential_ref_id: credential.credential_ref_id,
      connection_id: credential.connection_id,
      profile_id: credential.profile_id,
      subject: credential.subject,
      auth_type: credential.auth_type,
      version: credential.version,
      scopes: credential.scopes,
      lease_fields: credential.lease_fields,
      secret_envelope: SecretEnvelope.encrypt(credential.secret, credential.id),
      expires_at: credential.expires_at,
      refresh_token_expires_at: credential.refresh_token_expires_at,
      source: credential.source,
      source_ref: credential.source_ref,
      supersedes_credential_id: credential.supersedes_credential_id,
      revoked_at: credential.revoked_at,
      metadata: credential.metadata
    }

    {:ok, %{state | credentials: Map.put(state.credentials, credential.id, persisted)}}
  end

  @spec fetch_credential(t(), String.t()) :: {:ok, Credential.t()} | {:error, :unknown_credential}
  def fetch_credential(%__MODULE__{} = state, credential_id) do
    case Map.get(state.credentials, credential_id) do
      nil ->
        {:error, :unknown_credential}

      persisted ->
        {:ok,
         Credential.new!(%{
           id: persisted.id,
           credential_ref_id: persisted.credential_ref_id,
           connection_id: persisted.connection_id,
           profile_id: persisted.profile_id,
           subject: persisted.subject,
           auth_type: persisted.auth_type,
           version: persisted.version,
           scopes: persisted.scopes,
           lease_fields: persisted.lease_fields,
           secret: SecretEnvelope.decrypt(persisted.secret_envelope, persisted.id),
           expires_at: persisted.expires_at,
           refresh_token_expires_at: persisted.refresh_token_expires_at,
           source: persisted.source,
           source_ref: persisted.source_ref,
           supersedes_credential_id: persisted.supersedes_credential_id,
           revoked_at: persisted.revoked_at,
           metadata: persisted.metadata
         })}
    end
  end

  @spec store_connection(t(), Connection.t()) :: {:ok, t()}
  def store_connection(%__MODULE__{} = state, %Connection{} = connection) do
    {:ok,
     %{state | connections: Map.put(state.connections, connection.connection_id, connection)}}
  end

  @spec fetch_connection(t(), String.t()) :: {:ok, Connection.t()} | {:error, :unknown_connection}
  def fetch_connection(%__MODULE__{} = state, connection_id) do
    case Map.get(state.connections, connection_id) do
      nil -> {:error, :unknown_connection}
      connection -> {:ok, connection}
    end
  end

  @spec list_connections(t(), map()) :: [Connection.t()]
  def list_connections(%__MODULE__{} = state, filters \\ %{}) do
    state.connections
    |> Map.values()
    |> filter_records(filters)
    |> Enum.sort_by(&{&1.inserted_at, &1.connection_id})
  end

  @spec store_install(t(), Install.t()) :: {:ok, t()}
  def store_install(%__MODULE__{} = state, %Install{} = install) do
    {:ok, %{state | installs: Map.put(state.installs, install.install_id, install)}}
  end

  @spec fetch_install(t(), String.t()) :: {:ok, Install.t()} | {:error, :unknown_install}
  def fetch_install(%__MODULE__{} = state, install_id) do
    case Map.get(state.installs, install_id) do
      nil -> {:error, :unknown_install}
      install -> {:ok, install}
    end
  end

  @spec list_installs(t(), map()) :: [Install.t()]
  def list_installs(%__MODULE__{} = state, filters \\ %{}) do
    state.installs
    |> Map.values()
    |> filter_records(filters)
    |> Enum.sort_by(&{&1.inserted_at, &1.install_id})
  end

  @spec store_lease(t(), LeaseRecord.t()) :: {:ok, t()}
  def store_lease(%__MODULE__{} = state, %LeaseRecord{} = lease) do
    {:ok, %{state | leases: Map.put(state.leases, lease.lease_id, lease)}}
  end

  @spec fetch_lease(t(), String.t()) :: {:ok, LeaseRecord.t()} | {:error, :unknown_lease}
  def fetch_lease(%__MODULE__{} = state, lease_id) do
    case Map.get(state.leases, lease_id) do
      nil -> {:error, :unknown_lease}
      lease -> {:ok, lease}
    end
  end

  @spec put_run(t(), Run.t()) :: {:ok, t()} | {{:error, :duplicate_run}, t()}
  def put_run(%__MODULE__{} = state, %Run{} = run) do
    if Map.has_key?(state.runs, run.run_id) do
      {{:error, :duplicate_run}, state}
    else
      {:ok, %{state | runs: Map.put(state.runs, run.run_id, sanitize_run(run))}}
    end
  end

  @spec fetch_run(t(), String.t()) :: {:ok, Run.t()} | :error
  def fetch_run(%__MODULE__{} = state, run_id) do
    case Map.get(state.runs, run_id) do
      nil -> :error
      run -> {:ok, run}
    end
  end

  @spec list_runs(t()) :: [Run.t()]
  def list_runs(%__MODULE__{} = state) do
    state.runs
    |> Map.values()
    |> Enum.sort_by(&{&1.inserted_at, &1.run_id})
  end

  @spec update_run(t(), String.t(), atom(), map() | nil) ::
          {:ok, t()} | {{:error, :not_found}, t()}
  def update_run(%__MODULE__{} = state, run_id, status, result) do
    case Map.get(state.runs, run_id) do
      nil ->
        {{:error, :not_found}, state}

      %Run{} = run ->
        next_run = %{
          run
          | status: status,
            result: Redaction.redact(result),
            updated_at: Contracts.now()
        }

        {:ok, %{state | runs: Map.put(state.runs, run_id, next_run)}}
    end
  end

  @spec put_attempt(t(), Attempt.t()) :: {:ok, t()} | {{:error, :duplicate_attempt}, t()}
  def put_attempt(%__MODULE__{} = state, %Attempt{} = attempt) do
    if Map.has_key?(state.attempts, attempt.attempt_id) do
      {{:error, :duplicate_attempt}, state}
    else
      {:ok,
       %{state | attempts: Map.put(state.attempts, attempt.attempt_id, sanitize_attempt(attempt))}}
    end
  end

  @spec fetch_attempt(t(), String.t()) :: {:ok, Attempt.t()} | :error
  def fetch_attempt(%__MODULE__{} = state, attempt_id) do
    case Map.get(state.attempts, attempt_id) do
      nil -> :error
      attempt -> {:ok, attempt}
    end
  end

  @spec list_attempts(t(), String.t()) :: [Attempt.t()]
  def list_attempts(%__MODULE__{} = state, run_id) do
    state.attempts
    |> Map.values()
    |> Enum.filter(&(&1.run_id == run_id))
    |> Enum.sort_by(&{&1.attempt, &1.attempt_id})
  end

  @spec update_attempt(t(), String.t(), atom(), map() | nil, String.t() | nil, keyword()) ::
          {:ok, t()} | {{:error, :not_found | :stale_aggregator_epoch}, t()}
  def update_attempt(%__MODULE__{} = state, attempt_id, status, output, runtime_ref_id, opts) do
    case Map.get(state.attempts, attempt_id) do
      nil ->
        {{:error, :not_found}, state}

      %Attempt{} = attempt ->
        next_epoch = Keyword.get(opts, :aggregator_epoch, attempt.aggregator_epoch)

        if next_epoch < attempt.aggregator_epoch do
          {{:error, :stale_aggregator_epoch}, state}
        else
          next_attempt = %{
            attempt
            | status: status,
              output: Redaction.redact(output),
              runtime_ref_id: runtime_ref_id,
              aggregator_id: Keyword.get(opts, :aggregator_id, attempt.aggregator_id),
              aggregator_epoch: next_epoch,
              updated_at: Contracts.now()
          }

          {:ok, %{state | attempts: Map.put(state.attempts, attempt_id, next_attempt)}}
        end
    end
  end

  @spec next_seq(t(), String.t(), String.t() | nil) :: non_neg_integer()
  def next_seq(%__MODULE__{} = state, run_id, attempt_id) do
    state
    |> list_event_entries(run_id)
    |> Enum.count(&(attempt_key(run_id, &1.event.attempt_id) == attempt_key(run_id, attempt_id)))
  end

  @spec append_events(t(), [Event.t()], keyword()) :: {:ok, t()} | {{:error, term()}, t()}
  def append_events(%__MODULE__{} = state, [], _opts), do: {:ok, state}

  def append_events(%__MODULE__{} = state, events, opts) do
    with {:ok, prepared_state} <- validate_event_epoch(state, events, opts),
         {:ok, next_state} <- persist_events(prepared_state, events) do
      {:ok, next_state}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @spec list_events(t(), String.t()) :: [Event.t()]
  def list_events(%__MODULE__{} = state, run_id) do
    state
    |> list_event_entries(run_id)
    |> Enum.sort_by(fn entry ->
      {
        attempt_sort_key(entry.event.attempt),
        entry.event.seq,
        DateTime.to_unix(entry.inserted_at, :microsecond),
        entry.event.event_id
      }
    end)
    |> Enum.map(& &1.event)
  end

  @spec put_artifact_ref(t(), ArtifactRef.t()) :: {:ok, t()}
  def put_artifact_ref(%__MODULE__{} = state, %ArtifactRef{} = artifact_ref) do
    {:ok, %{state | artifacts: Map.put(state.artifacts, artifact_ref.artifact_id, artifact_ref)}}
  end

  @spec fetch_artifact_ref(t(), String.t()) :: {:ok, ArtifactRef.t()} | :error
  def fetch_artifact_ref(%__MODULE__{} = state, artifact_id) do
    case Map.get(state.artifacts, artifact_id) do
      nil -> :error
      artifact_ref -> {:ok, artifact_ref}
    end
  end

  @spec list_artifact_refs(t(), String.t()) :: [ArtifactRef.t()]
  def list_artifact_refs(%__MODULE__{} = state, run_id) do
    state.artifacts
    |> Map.values()
    |> Enum.filter(&(&1.run_id == run_id))
    |> Enum.sort_by(& &1.artifact_id)
  end

  @spec put_target_descriptor(t(), TargetDescriptor.t()) :: {:ok, t()}
  def put_target_descriptor(%__MODULE__{} = state, %TargetDescriptor{} = descriptor) do
    {:ok, %{state | targets: Map.put(state.targets, descriptor.target_id, descriptor)}}
  end

  @spec fetch_target_descriptor(t(), String.t()) :: {:ok, TargetDescriptor.t()} | :error
  def fetch_target_descriptor(%__MODULE__{} = state, target_id) do
    case Map.get(state.targets, target_id) do
      nil -> :error
      descriptor -> {:ok, descriptor}
    end
  end

  @spec list_target_descriptors(t()) :: [TargetDescriptor.t()]
  def list_target_descriptors(%__MODULE__{} = state) do
    state.targets
    |> Map.values()
    |> Enum.sort_by(& &1.target_id)
  end

  @spec install_profile_registry_entry(
          t(),
          map() | keyword() | ServiceSimulationProfile.t(),
          [map()],
          map()
        ) ::
          {{:ok, SimulationProfileRegistryEntry.t()} | {:error, atom()}, t()}
  def install_profile_registry_entry(%__MODULE__{} = state, profile, installed_scenarios, attrs) do
    case SimulationProfileRegistryEntry.install(profile, installed_scenarios, attrs) do
      {:ok, entry} -> install_profile_registry_entry(state, entry)
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @spec update_profile_registry_entry(
          t(),
          map() | keyword() | ServiceSimulationProfile.t(),
          [map()],
          map()
        ) ::
          {{:ok, SimulationProfileRegistryEntry.t()} | {:error, atom()}, t()}
  def update_profile_registry_entry(%__MODULE__{} = state, profile, installed_scenarios, attrs) do
    case profile_id_from(profile) do
      nil ->
        {{:error, :unknown_profile}, state}

      profile_id ->
        update_profile_registry_entry(state, profile_id, profile, installed_scenarios, attrs)
    end
  end

  @spec remove_profile_registry_entry(t(), String.t(), map()) ::
          {{:ok, SimulationProfileRegistryEntry.t()} | {:error, atom()}, t()}
  def remove_profile_registry_entry(%__MODULE__{} = state, profile_id, attrs) do
    remove_profile_registry_entry(
      state,
      profile_id,
      Map.fetch(state.profile_registry_entries, profile_id),
      attrs
    )
  end

  @spec fetch_profile_registry_entry(t(), String.t()) ::
          {:ok, SimulationProfileRegistryEntry.t()} | :error
  def fetch_profile_registry_entry(%__MODULE__{} = state, profile_id) do
    case Map.fetch(state.profile_registry_entries, profile_id) do
      {:ok, entry} -> {:ok, entry}
      :error -> :error
    end
  end

  @spec select_profile_registry_entry(t(), String.t(), String.t(), String.t()) ::
          {:ok, SimulationProfileRegistryEntry.t()} | {:error, atom()} | :error
  def select_profile_registry_entry(
        %__MODULE__{} = state,
        profile_id,
        environment_scope,
        owner_ref
      ) do
    with {:ok, entry} <- fetch_profile_registry_entry(state, profile_id) do
      SimulationProfileRegistryEntry.select(entry, environment_scope, owner_ref)
    end
  end

  @spec list_profile_registry_entries(t(), map()) :: [SimulationProfileRegistryEntry.t()]
  def list_profile_registry_entries(%__MODULE__{} = state, filters \\ %{}) do
    state.profile_registry_entries
    |> Map.values()
    |> filter_records(filters)
    |> Enum.sort_by(&{&1.audit_install_timestamp, &1.profile_id})
  end

  @spec reserve_dedupe(t(), String.t(), String.t(), String.t(), String.t(), DateTime.t()) ::
          {:ok, t()} | {{:error, :duplicate}, t()}
  def reserve_dedupe(
        %__MODULE__{} = state,
        tenant_id,
        connector_id,
        trigger_id,
        dedupe_key,
        expires_at
      ) do
    scope = dedupe_scope(tenant_id, connector_id, trigger_id, dedupe_key)

    if Map.has_key?(state.dedupe, scope) do
      {{:error, :duplicate}, state}
    else
      {:ok, %{state | dedupe: Map.put(state.dedupe, scope, expires_at)}}
    end
  end

  @spec put_trigger(t(), TriggerRecord.t()) :: {:ok, t()}
  def put_trigger(%__MODULE__{} = state, %TriggerRecord{} = trigger) do
    scope =
      dedupe_scope(
        trigger.tenant_id,
        trigger.connector_id,
        trigger.trigger_id,
        trigger.dedupe_key
      )

    {:ok, %{state | triggers: Map.put(state.triggers, scope, trigger)}}
  end

  @spec fetch_trigger(t(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, TriggerRecord.t()} | :error
  def fetch_trigger(%__MODULE__{} = state, tenant_id, connector_id, trigger_id, dedupe_key) do
    scope = dedupe_scope(tenant_id, connector_id, trigger_id, dedupe_key)

    case Map.get(state.triggers, scope) do
      nil -> :error
      trigger -> {:ok, trigger}
    end
  end

  @spec list_run_triggers(t(), String.t()) :: [TriggerRecord.t()]
  def list_run_triggers(%__MODULE__{} = state, run_id) do
    state.triggers
    |> Map.values()
    |> Enum.filter(&(&1.run_id == run_id))
    |> Enum.sort_by(fn trigger ->
      {DateTime.to_unix(trigger.inserted_at, :microsecond), trigger.admission_id}
    end)
  end

  @spec put_checkpoint(t(), TriggerCheckpoint.t()) :: {:ok, t()}
  def put_checkpoint(%__MODULE__{} = state, %TriggerCheckpoint{} = checkpoint) do
    key =
      checkpoint_key(
        checkpoint.tenant_id,
        checkpoint.connector_id,
        checkpoint.trigger_id,
        checkpoint.partition_key
      )

    next_checkpoint =
      case Map.get(state.checkpoints, key) do
        nil ->
          checkpoint

        %TriggerCheckpoint{} = current ->
          %{
            checkpoint
            | revision: current.revision + 1,
              updated_at: Contracts.now()
          }
      end

    {:ok, %{state | checkpoints: Map.put(state.checkpoints, key, next_checkpoint)}}
  end

  @spec fetch_checkpoint(t(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, TriggerCheckpoint.t()} | :error
  def fetch_checkpoint(%__MODULE__{} = state, tenant_id, connector_id, trigger_id, partition_key) do
    key = checkpoint_key(tenant_id, connector_id, trigger_id, partition_key)

    case Map.get(state.checkpoints, key) do
      nil -> :error
      checkpoint -> {:ok, checkpoint}
    end
  end

  @spec accept_submission(t(), BrainInvocation.t()) ::
          {{:ok, SubmissionAcceptance.t()} | {:error, term()}, t()}
  def accept_submission(%__MODULE__{} = state, %BrainInvocation{} = invocation) do
    tenant_id = invocation.tenant_id
    submission_dedupe_key = SubmissionDedupe.key!(invocation)
    identity_checksum = SubmissionIdentity.submission_key(invocation.submission_identity)
    key = {tenant_id, submission_dedupe_key}
    now = Contracts.now()
    expires_at = DateTime.add(now, 14 * 86_400, :second)

    case Map.get(state.expired_submissions, key) do
      %{last_seen_at: %DateTime{} = last_seen_at} ->
        {{:error, {:expired_submission_dedupe_key, last_seen_at}}, state}

      nil ->
        case Map.get(state.submissions, key) do
          nil ->
            acceptance =
              SubmissionAcceptance.new!(%{
                submission_key: invocation.submission_key,
                submission_receipt_ref: "submission://local/#{invocation.submission_key}",
                status: :accepted,
                accepted_at: now,
                ledger_version: map_size(state.submissions) + 1
              })

            next_state =
              state
              |> put_in([Access.key(:submissions), key], %{
                submission_key: invocation.submission_key,
                identity_checksum: identity_checksum,
                acceptance: acceptance,
                rejection: nil,
                last_seen_at: now,
                expires_at: expires_at
              })
              |> put_in(
                [Access.key(:submission_acceptances), invocation.submission_key],
                acceptance
              )

            {{:ok, acceptance}, next_state}

          %{
            identity_checksum: ^identity_checksum,
            acceptance: %SubmissionAcceptance{} = acceptance
          } = entry ->
            duplicate =
              SubmissionAcceptance.new!(%{
                SubmissionAcceptance.dump(acceptance)
                | status: :duplicate
              })

            next_state =
              put_in(state.submissions[key], %{
                entry
                | last_seen_at: now,
                  expires_at: expires_at
              })

            {{:ok, duplicate}, next_state}

          _other ->
            {{:error, :conflicting_submission}, state}
        end
    end
  end

  @spec lookup_submission(t(), String.t(), String.t()) ::
          {:accepted, SubmissionAcceptance.t()}
          | {:rejected, SubmissionRejection.t()}
          | :never_seen
          | {:expired, DateTime.t()}
  def lookup_submission(%__MODULE__{} = state, submission_dedupe_key, tenant_id) do
    key = {tenant_id, submission_dedupe_key}
    now = Contracts.now()

    case Map.get(state.submissions, key) do
      %{acceptance: %SubmissionAcceptance{} = acceptance, expires_at: expires_at} = entry ->
        if DateTime.compare(expires_at, now) == :gt do
          {:accepted, acceptance}
        else
          {:expired, entry.last_seen_at}
        end

      %{rejection: %SubmissionRejection{} = rejection, expires_at: expires_at} = entry ->
        if DateTime.compare(expires_at, now) == :gt do
          {:rejected, rejection}
        else
          {:expired, entry.last_seen_at}
        end

      %{last_seen_at: %DateTime{} = last_seen_at} ->
        {:expired, last_seen_at}

      nil ->
        case Map.get(state.expired_submissions, key) do
          %{last_seen_at: %DateTime{} = last_seen_at} -> {:expired, last_seen_at}
          _other -> :never_seen
        end
    end
  end

  @spec fetch_submission_acceptance(t(), String.t(), String.t() | nil) ::
          {:ok, SubmissionAcceptance.t()} | {:error, :tenant_mismatch} | :error
  def fetch_submission_acceptance(%__MODULE__{} = state, submission_key, authorized_tenant_id) do
    state.submissions
    |> Enum.find_value(fn
      {{tenant_id, _submission_dedupe_key},
       %{submission_key: ^submission_key, acceptance: acceptance}} ->
        {tenant_id, acceptance}

      _other ->
        nil
    end)
    |> case do
      {tenant_id, %SubmissionAcceptance{} = acceptance} ->
        with :ok <- authorize_submission_tenant(tenant_id, authorized_tenant_id),
             do: {:ok, acceptance}

      _other ->
        :error
    end
  end

  defp authorize_submission_tenant(_tenant_id, nil), do: :ok
  defp authorize_submission_tenant(tenant_id, tenant_id), do: :ok

  defp authorize_submission_tenant(_tenant_id, _authorized_tenant_id),
    do: {:error, :tenant_mismatch}

  @spec record_submission_rejection(t(), BrainInvocation.t(), SubmissionRejection.t()) ::
          {:ok, t()}
  def record_submission_rejection(
        %__MODULE__{} = state,
        %BrainInvocation{} = invocation,
        %SubmissionRejection{} = rejection
      ) do
    tenant_id = invocation.tenant_id
    submission_dedupe_key = SubmissionDedupe.key!(invocation)
    identity_checksum = SubmissionIdentity.submission_key(invocation.submission_identity)
    key = {tenant_id, submission_dedupe_key}
    now = Contracts.now()
    expires_at = DateTime.add(now, 14 * 86_400, :second)

    case Map.get(state.expired_submissions, key) do
      %{last_seen_at: %DateTime{} = _last_seen_at} ->
        {:ok, state}

      nil ->
        case Map.get(state.submissions, key) do
          nil ->
            entry = %{
              submission_key: invocation.submission_key,
              identity_checksum: identity_checksum,
              acceptance: nil,
              rejection: rejection,
              last_seen_at: now,
              expires_at: expires_at
            }

            {:ok,
             state
             |> put_in([Access.key(:submissions), key], entry)
             |> put_in([Access.key(:submission_rejections), invocation.submission_key], rejection)}

          %{identity_checksum: ^identity_checksum} = entry ->
            {:ok,
             state
             |> put_in([Access.key(:submissions), key], %{
               entry
               | rejection: rejection,
                 acceptance: nil,
                 last_seen_at: now,
                 expires_at: expires_at
             })
             |> put_in([Access.key(:submission_rejections), invocation.submission_key], rejection)}

          _other ->
            {:ok, state}
        end
    end
  end

  @spec expire_submissions(t(), DateTime.t() | nil) :: {non_neg_integer(), t()}
  def expire_submissions(%__MODULE__{} = state, now \\ nil) do
    now = now || Contracts.now()

    {expired, live} =
      Enum.split_with(state.submissions, fn {_key, entry} ->
        DateTime.compare(entry.expires_at, now) != :gt
      end)

    expired_submissions =
      Enum.reduce(expired, state.expired_submissions, fn {{tenant_id, submission_dedupe_key},
                                                          entry},
                                                         acc ->
        Map.put(acc, {tenant_id, submission_dedupe_key}, %{
          submission_key: entry.submission_key,
          status: if(entry.acceptance, do: :accepted, else: :rejected),
          last_seen_at: entry.last_seen_at
        })
      end)

    {length(expired),
     %{
       state
       | submissions: Map.new(live),
         expired_submissions: expired_submissions
     }}
  end

  defp validate_event_epoch(state, [%Event{attempt_id: nil}], _opts), do: {:ok, state}
  defp validate_event_epoch(state, [%Event{attempt_id: nil} | _rest], _opts), do: {:ok, state}

  defp validate_event_epoch(%__MODULE__{} = state, [%Event{attempt_id: attempt_id} | _rest], opts) do
    case Map.get(state.attempts, attempt_id) do
      nil ->
        {:error, :unknown_attempt}

      %Attempt{} = attempt ->
        next_epoch = Keyword.get(opts, :aggregator_epoch, attempt.aggregator_epoch)
        next_id = Keyword.get(opts, :aggregator_id, attempt.aggregator_id)
        validate_event_epoch(state, attempt, attempt_id, next_epoch, next_id)
    end
  end

  defp validate_event_epoch(
         %__MODULE__{} = _state,
         %Attempt{} = attempt,
         _attempt_id,
         next_epoch,
         _next_id
       )
       when next_epoch < attempt.aggregator_epoch do
    {:error, :stale_aggregator_epoch}
  end

  defp validate_event_epoch(
         %__MODULE__{} = _state,
         %Attempt{} = attempt,
         _attempt_id,
         next_epoch,
         next_id
       )
       when next_epoch == attempt.aggregator_epoch and next_id != attempt.aggregator_id do
    {:error, :aggregator_id_mismatch}
  end

  defp validate_event_epoch(
         %__MODULE__{} = state,
         %Attempt{} = attempt,
         attempt_id,
         next_epoch,
         next_id
       )
       when next_epoch > attempt.aggregator_epoch do
    next_attempt = %{attempt | aggregator_id: next_id, aggregator_epoch: next_epoch}
    {:ok, %{state | attempts: Map.put(state.attempts, attempt_id, next_attempt)}}
  end

  defp validate_event_epoch(%__MODULE__{} = state, %Attempt{}, _attempt_id, _next_epoch, _next_id) do
    {:ok, state}
  end

  defp persist_events(%__MODULE__{} = state, events) do
    Enum.reduce_while(events, {:ok, state}, fn event, {:ok, acc_state} ->
      sanitized_event = sanitize_event(event)

      case append_event(acc_state, sanitized_event) do
        {:ok, next_state} -> {:cont, {:ok, next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp append_event(%__MODULE__{} = state, %Event{} = event) do
    entries = list_event_entries(state, event.run_id)

    case Enum.find(entries, &same_position?(&1.event, event)) do
      nil ->
        next_entries = entries ++ [%{event: event, inserted_at: Contracts.now()}]
        {:ok, %{state | events: Map.put(state.events, event.run_id, next_entries)}}

      %{event: existing_event} ->
        if existing_event == event do
          {:ok, state}
        else
          {:error, :event_conflict}
        end
    end
  end

  defp list_event_entries(%__MODULE__{} = state, run_id) do
    Map.get(state.events, run_id, [])
  end

  defp sanitize_run(%Run{} = run) do
    %{run | input: Redaction.redact(run.input), result: Redaction.redact(run.result)}
  end

  defp sanitize_attempt(%Attempt{} = attempt) do
    %{attempt | output: Redaction.redact(attempt.output)}
  end

  defp sanitize_event(%Event{} = event) do
    %{event | payload: Redaction.redact(event.payload)}
  end

  defp install_profile_registry_entry(state, entry) do
    case Map.fetch(state.profile_registry_entries, entry.profile_id) do
      {:ok, existing} when existing.profile_version != entry.profile_version ->
        {{:error, :concurrent_install_same_id_different_version}, state}

      {:ok, existing} ->
        {{:ok, existing}, state}

      :error ->
        {{:ok, entry}, put_profile_registry_entry(state, entry)}
    end
  end

  defp update_profile_registry_entry(state, profile_id, profile, installed_scenarios, attrs) do
    case Map.fetch(state.profile_registry_entries, profile_id) do
      {:ok, current} ->
        current
        |> SimulationProfileRegistryEntry.update(profile, installed_scenarios, attrs)
        |> put_updated_profile_registry_entry(state)

      :error ->
        {{:error, :unknown_profile}, state}
    end
  end

  defp put_updated_profile_registry_entry({:ok, updated}, state) do
    {{:ok, updated}, put_profile_registry_entry(state, updated)}
  end

  defp put_updated_profile_registry_entry({:error, reason}, state), do: {{:error, reason}, state}

  defp remove_profile_registry_entry(state, profile_id, {:ok, current}, attrs) do
    current
    |> remove_registry_entry(attrs)
    |> put_removed_profile_registry_entry(state, profile_id)
  end

  defp remove_profile_registry_entry(state, _profile_id, :error, _attrs) do
    {{:error, :unknown_profile}, state}
  end

  defp put_removed_profile_registry_entry({:ok, removed, reply}, state, profile_id) do
    {reply, put_profile_registry_entry(state, profile_id, removed)}
  end

  defp put_removed_profile_registry_entry({:error, reason}, state, _profile_id) do
    {{:error, reason}, state}
  end

  defp put_profile_registry_entry(state, entry) do
    put_profile_registry_entry(state, entry.profile_id, entry)
  end

  defp put_profile_registry_entry(state, profile_id, entry) do
    %{
      state
      | profile_registry_entries: Map.put(state.profile_registry_entries, profile_id, entry)
    }
  end

  defp remove_registry_entry(%SimulationProfileRegistryEntry{} = current, attrs) do
    removed = SimulationProfileRegistryEntry.remove!(current, attrs)

    reply =
      case removed.cleanup_status do
        :cleanup_failed -> {:error, :cleanup_failure}
        :removed -> {:ok, removed}
      end

    {:ok, removed, reply}
  rescue
    error in ArgumentError ->
      {:error, registry_failure_reason(error)}
  end

  defp registry_failure_reason(%ArgumentError{message: message}) do
    if String.contains?(message, "cleanup"), do: :cleanup_failure, else: :invalid_registry_entry
  end

  defp profile_id_from(%ServiceSimulationProfile{} = profile), do: profile.profile_id

  defp profile_id_from(profile) when is_map(profile) or is_list(profile) do
    profile
    |> Map.new()
    |> Contracts.get(:profile_id)
  end

  defp profile_id_from(_profile), do: nil

  defp filter_records(records, filters) when is_map(filters) do
    Enum.filter(records, fn record ->
      Enum.all?(filters, fn {key, value} -> Map.get(record, key) == value end)
    end)
  end

  defp same_position?(%Event{} = left, %Event{} = right) do
    left.run_id == right.run_id and left.attempt_id == right.attempt_id and left.seq == right.seq
  end

  defp attempt_key(run_id, nil), do: "#{run_id}:run"
  defp attempt_key(_run_id, attempt_id), do: attempt_id

  defp attempt_sort_key(nil), do: 0
  defp attempt_sort_key(attempt), do: attempt

  defp checkpoint_key(tenant_id, connector_id, trigger_id, partition_key) do
    {tenant_id, connector_id, trigger_id, partition_key}
  end

  defp dedupe_scope(tenant_id, connector_id, trigger_id, dedupe_key) do
    {tenant_id, connector_id, trigger_id, dedupe_key}
  end
end
