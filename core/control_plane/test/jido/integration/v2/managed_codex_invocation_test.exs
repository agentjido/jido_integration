defmodule Jido.Integration.V2.ManagedCodexInvocationTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Auth.ManagedAccount
  alias Jido.Integration.V2.Auth.Persistence, as: AuthPersistence
  alias Jido.Integration.V2.AuthSpec
  alias Jido.Integration.V2.CatalogSpec
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.ControlPlane.Persistence, as: ControlPlanePersistence
  alias Jido.Integration.V2.ControlPlane.RuntimeConfig
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.MaterializationRequest
  alias Jido.Integration.V2.OperationSpec
  alias Jido.Integration.V2.RuntimeResult
  alias Jido.Integration.V2.SecretMaterial

  defmodule Handler do
    use Jido.Action,
      name: "managed_codex_test_handler",
      schema: [prompt: [type: :string, required: true]]

    @impl true
    def run(_params, _context), do: {:error, :direct_handler_must_not_run}
  end

  defmodule Connector do
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "managed_codex_test",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :api_token,
            install: %{required: true},
            reauth: %{supported: false},
            requested_scopes: ["session:execute"],
            lease_fields: ["auth_json"],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "Managed Codex Test",
            description: "Deterministic managed Codex lifecycle proof",
            category: "test",
            tags: ["codex", "managed"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [
          OperationSpec.new!(%{
            operation_id: "codex.session.turn",
            name: "managed_codex_turn",
            display_name: "Managed Codex turn",
            description: "Exercises the governed managed Codex session lane",
            runtime_class: :session,
            transport_mode: :app_server,
            handler: Handler,
            input_schema: Zoi.object(%{prompt: Zoi.string()}),
            output_schema:
              Zoi.object(%{
                content: Zoi.string(),
                cleanup:
                  Zoi.object(%{
                    session: Zoi.string(),
                    materialization: Zoi.string()
                  })
                  |> Zoi.optional()
              }),
            permissions: %{required_scopes: ["session:execute"]},
            runtime: %{driver: "asm", provider: :codex, options: %{app_server: true}},
            policy: %{
              environment: %{allowed: [:prod]},
              sandbox: %{
                level: :strict,
                egress: :restricted,
                approvals: :manual,
                file_scope: "runtime_bound",
                allowed_tools: ["codex.session.turn"]
              }
            },
            upstream: %{protocol: :app_server},
            consumer_surface: %{
              mode: :common,
              normalized_id: "codex.session.turn",
              action_name: "codex_session_turn"
            },
            schema_policy: %{input: :defined, output: :defined},
            jido: %{action: %{name: "codex_session_turn"}},
            metadata: %{
              session_control: %{operation: :turn},
              runtime_family: %{
                session_affinity: :connection,
                resumable: true,
                approval_required: true,
                stream_capable: true,
                lifecycle_owner: :asm,
                runtime_ref: :session
              }
            }
          })
        ],
        triggers: [],
        runtime_families: [:session]
      })
    end
  end

  defmodule ManagedAccountStore do
    @behaviour Jido.Integration.V2.Auth.ManagedAccountStore

    use Agent

    def start_link(_opts),
      do: Agent.start_link(fn -> %{accounts: %{}, versions: %{}} end, name: __MODULE__)

    @impl true
    def transact(fun), do: fun.()

    @impl true
    def register(account, version) do
      Agent.get_and_update(__MODULE__, fn state ->
        if Map.has_key?(state.accounts, account.account_ref) do
          {{:error, :account_exists}, state}
        else
          {:ok,
           state
           |> put_in([:accounts, account.account_ref], account)
           |> put_in([:versions, {account.account_ref, version.generation}], version)}
        end
      end)
    end

    @impl true
    def fetch(account_ref) do
      Agent.get(__MODULE__, fn state ->
        case Map.fetch(state.accounts, account_ref) do
          {:ok, account} -> {:ok, account}
          :error -> {:error, :unknown_managed_account}
        end
      end)
    end

    @impl true
    def lock(account_ref), do: fetch(account_ref)

    @impl true
    def fetch_by_connection(connection_id) do
      Agent.get(__MODULE__, fn state ->
        case Enum.find(Map.values(state.accounts), &(&1.connection_id == connection_id)) do
          nil -> {:error, :unknown_managed_account}
          account -> {:ok, account}
        end
      end)
    end

    @impl true
    def fetch_version(account_ref, generation) do
      Agent.get(__MODULE__, fn state ->
        case Map.fetch(state.versions, {account_ref, generation}) do
          {:ok, version} -> {:ok, version}
          :error -> {:error, :unknown_credential_generation}
        end
      end)
    end

    @impl true
    def rotate(_account_ref, _generation, _fence, _version, _now),
      do: {:error, :unsupported_in_test}

    @impl true
    def revoke(_account_ref, _generation, _fence, _revocation_ref, _now),
      do: {:error, :unsupported_in_test}
  end

  defmodule CredentialMaterializer do
    @behaviour Jido.Integration.V2.CredentialMaterializer

    @impl true
    def materialize(_lease, request) do
      SecretMaterial.new(%{
        materialization_ref: request.materialization_ref,
        provider_family: request.account.provider_family,
        account_ref: request.account.account_ref,
        generation: request.account.generation,
        payload: %{
          auth_json: %{"token" => "managed-codex-secret-sentinel"}
        }
      })
    end

    @impl true
    def revoke(_material, _opts), do: :ok
  end

  defmodule RuntimeRecorder do
    use Agent

    def start_link(_opts), do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def record(event), do: Agent.update(__MODULE__, &[event | &1])
    def events, do: Agent.get(__MODULE__, &Enum.reverse/1)
  end

  defmodule RuntimeClientGateway do
    @behaviour CliSubprocessCore.RuntimeGateway

    @impl true
    def start_session(_request), do: {:error, :not_started_by_projection_test}
    @impl true
    def send_input(_session, _input), do: :ok
    @impl true
    def end_input(_session), do: :ok
    @impl true
    def info(_session), do: {:error, :not_started_by_projection_test}
    @impl true
    def subscribe(_session, _subscriber), do: :ok
    @impl true
    def cancel(_session, _reason), do: :ok
    @impl true
    def terminate(_session, _reason), do: :ok
  end

  defmodule EffectRuntimeClient do
    @behaviour ExecutionPlane.Runtime.Client

    @impl true
    def start(_request, _opts), do: {:error, :not_started_by_projection_test}
    @impl true
    def subscribe(_execution_ref, _subscriber, _opts), do: :ok
    @impl true
    def send_input(_execution_ref, _input, _opts), do: :ok
    @impl true
    def end_input(_execution_ref, _opts), do: :ok
    @impl true
    def status(_execution_ref, _opts), do: {:error, :not_started_by_projection_test}
    @impl true
    def cancel(_execution_ref, _opts), do: :ok
  end

  defmodule RuntimeAdapter do
    @session_id "managed-codex-runtime-test"

    def execute(_capability, _input, context) do
      runtime_opts = context.opts.managed_runtime_opts
      secret_material = Keyword.fetch!(runtime_opts, :secret_material)
      runtime = secret_material.payload
      auth_path = Path.join(runtime.config_root, "auth.json")

      auth_valid? =
        File.regular?(auth_path) and
          File.read!(auth_path) =~ "managed-codex-secret-sentinel" and
          File.stat!(auth_path).mode |> Bitwise.band(0o777) == 0o600

      RuntimeRecorder.record(%{
        type: :execute,
        auth_valid?: auth_valid?,
        config_root: runtime.config_root,
        materialization_ref: runtime.materialization_ref,
        session_ref: Keyword.fetch!(runtime_opts, :managed_session).session_ref,
        execution_mode: Keyword.fetch!(runtime_opts, :execution_mode),
        runtime_gateway_module: Keyword.fetch!(runtime_opts, :runtime_gateway_module),
        runtime_gateway_ref: Keyword.fetch!(runtime_opts, :runtime_gateway_ref),
        runtime_client: Keyword.get(runtime_opts, :runtime_client),
        runtime_client_opts: Keyword.get(runtime_opts, :runtime_client_opts),
        runtime_attestation_classes: Keyword.get(runtime_opts, :runtime_attestation_classes),
        secret_redacted?: not (inspect(secret_material) =~ "managed-codex-secret-sentinel")
      })

      {:ok,
       RuntimeResult.new!(%{
         output: %{content: "managed Codex completed"},
         runtime_ref_id: @session_id,
         events: [%{type: "connector.codex_cli.turn.completed"}],
         artifacts: []
       })}
    end

    def cleanup_runtime_session(@session_id, :effect_scope_closed) do
      RuntimeRecorder.record(%{type: :cleanup, session_id: @session_id})
      :ok
    end
  end

  setup do
    start_supervised!(ManagedAccountStore)
    start_supervised!(RuntimeRecorder)

    previous_materializer =
      Application.get_env(:jido_integration_v2_control_plane, :codex_materializer)

    root =
      Path.join(
        System.tmp_dir!(),
        "jido-managed-codex-test-#{System.unique_integer([:positive])}"
      )

    workspace_root = Path.join(root, "workspace")
    session_root_parent = Path.join(root, "sessions")
    File.mkdir_p!(workspace_root)

    ControlPlanePersistence.reset!()
    AuthPersistence.reset!()

    ControlPlanePersistence.configure!(
      profile: :mickey_mouse,
      store_modules: ControlPlanePersistence.test_store_modules()
    )

    AuthPersistence.configure!(
      profile: :mickey_mouse,
      store_modules: AuthPersistence.test_store_modules()
    )

    ControlPlane.reset!()

    Auth.configure_managed_accounts!(
      store: ManagedAccountStore,
      materializers: %{"codex" => CredentialMaterializer}
    )

    :ok = RuntimeConfig.put(:non_direct_runtime_adapter, RuntimeAdapter)

    Application.put_env(:jido_integration_v2_control_plane, :codex_materializer,
      command: System.find_executable("true"),
      session_root_parent: session_root_parent
    )

    on_exit(fn ->
      File.rm_rf(root)
      ControlPlanePersistence.reset!()
      AuthPersistence.reset!()

      if previous_materializer do
        Application.put_env(
          :jido_integration_v2_control_plane,
          :codex_materializer,
          previous_materializer
        )
      else
        Application.delete_env(:jido_integration_v2_control_plane, :codex_materializer)
      end
    end)

    {:ok, workspace_root: workspace_root, session_root_parent: session_root_parent}
  end

  test "managed Codex session is materialized after admission and cleaned before return",
       context do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, %{account: %ManagedAccount{} = account, account_ref: account_ref}} =
             Auth.register_managed_account(registration(now))

    lease_context = lease_context(account, now)
    assert {:ok, lease} = Auth.request_managed_lease(account_ref, lease_context)

    request =
      MaterializationRequest.new!(%{
        materialization_ref: "materialization://codex/test/1",
        lease_id: lease.lease_id,
        account: account_ref,
        effect_ref: lease_context.effect_ref,
        operation_ref: lease_context.operation_ref,
        authority_ref: lease_context.authority_ref,
        endpoint_ref: account.endpoint_ref,
        target_ref: lease_context.target_ref,
        issued_at: now,
        expires_at: DateTime.add(now, 30, :second)
      })

    assert :ok = ControlPlane.register_connector(Connector)

    invoke_opts =
      managed_invoke_opts(
        lease,
        request,
        lease_context,
        now,
        context.workspace_root
      )

    assert_raise ArgumentError, ~r/api_key is forbidden/, fn ->
      ControlPlane.invoke_managed_session(
        "codex.session.turn",
        %{prompt: "create the reviewed file"},
        Keyword.put(invoke_opts, :api_key, "caller-secret-must-not-enter")
      )
    end

    assert {:ok, result} =
             ControlPlane.invoke_managed_session(
               "codex.session.turn",
               %{prompt: "create the reviewed file"},
               invoke_opts
             )

    assert result.run.status == :completed
    assert result.run.run_id == "jido-run://managed-codex/test/1"
    assert result.attempt.attempt_id == "jido-run://managed-codex/test/1:1"
    assert result.attempt.status == :completed
    assert result.output.content == "managed Codex completed"
    assert result.output.cleanup == %{session: "completed", materialization: "completed"}

    assert [
             %{
               type: :execute,
               auth_valid?: true,
               secret_redacted?: true,
               config_root: config_root,
               materialization_ref: "materialization://codex/test/1",
               session_ref: "managed-session://codex/test/1",
               execution_mode: :local,
               runtime_gateway_module: CliSubprocessCore.RuntimeGateway.Local,
               runtime_gateway_ref: "runtime-gateway://cli-subprocess-core/local/v1",
               runtime_client: nil,
               runtime_client_opts: nil
             },
             %{type: :cleanup, session_id: "managed-codex-runtime-test"}
           ] = RuntimeRecorder.events()

    refute File.exists?(config_root)
    assert File.ls!(context.session_root_parent) == []

    durable_snapshot = inspect({result, ControlPlane.events(result.run.run_id)})
    refute durable_snapshot =~ "managed-codex-secret-sentinel"
    refute durable_snapshot =~ "auth.json"
  end

  test "runtime-admitted managed invocation requires an explicit non-local gateway",
       context do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, %{account: %ManagedAccount{} = account, account_ref: account_ref}} =
             Auth.register_managed_account(registration(now))

    lease_context = lease_context(account, now)
    assert {:ok, lease} = Auth.request_managed_lease(account_ref, lease_context)

    request =
      MaterializationRequest.new!(%{
        materialization_ref: "materialization://codex/test/runtime",
        lease_id: lease.lease_id,
        account: account_ref,
        effect_ref: lease_context.effect_ref,
        operation_ref: lease_context.operation_ref,
        authority_ref: lease_context.authority_ref,
        endpoint_ref: account.endpoint_ref,
        target_ref: lease_context.target_ref,
        issued_at: now,
        expires_at: DateTime.add(now, 30, :second)
      })

    assert :ok = ControlPlane.register_connector(Connector)

    base_opts =
      managed_invoke_opts(lease, request, lease_context, now, context.workspace_root)
      |> Keyword.put(:managed_session_ref, "managed-session://codex/test/runtime")
      |> Keyword.put(:run_id, "jido-run://managed-codex/test/runtime")
      |> Keyword.put(:runtime_gateway_mode, :runtime)

    assert {:error, {:managed_session_option_required, :runtime_gateway_module}} =
             ControlPlane.invoke_managed_session(
               "codex.session.turn",
               %{prompt: "must not silently run locally"},
               base_opts
             )

    runtime_opts =
      base_opts
      |> Keyword.put(:runtime_gateway_module, RuntimeClientGateway)
      |> Keyword.put(
        :runtime_gateway_ref,
        "runtime-gateway://cli-subprocess-core/runtime-client/v1"
      )
      |> Keyword.put(:runtime_client, EffectRuntimeClient)
      |> Keyword.put(:runtime_attestation_classes, ["local-erlexec-weak"])
      |> Keyword.put(
        :runtime_client_opts,
        server: {:execution_plane_node, :effect_node@localhost},
        timeout: 5_000
      )

    assert {:ok, result} =
             ControlPlane.invoke_managed_session(
               "codex.session.turn",
               %{prompt: "route through Runtime Client"},
               runtime_opts
             )

    assert result.run.status == :completed

    assert [
             %{
               type: :execute,
               execution_mode: :runtime,
               runtime_gateway_module: RuntimeClientGateway,
               runtime_gateway_ref: "runtime-gateway://cli-subprocess-core/runtime-client/v1",
               runtime_client: EffectRuntimeClient,
               runtime_attestation_classes: ["local-erlexec-weak"],
               runtime_client_opts: [
                 fence: 0,
                 server: {:execution_plane_node, :effect_node@localhost},
                 timeout: 5_000
               ]
             },
             %{type: :cleanup, session_id: "managed-codex-runtime-test"}
           ] = RuntimeRecorder.events()
  end

  defp registration(now) do
    %{
      provider_family: "codex",
      account_ref: "provider-account://tenant-1/codex/developer",
      tenant_id: "tenant-1",
      connector_id: "codex_cli",
      endpoint_ref: "endpoint://codex/app-server",
      quota_scope_ref: "quota://codex/developer",
      credential_handle_ref: "credential-handle://codex/developer/v1",
      secret_provider_ref: "vault://nshkr/codex",
      secret_binding_ref: "vault-secret://codex/developer/v1",
      subject: "nshkr-codex-runtime",
      actor_id: "operator-1",
      scopes: ["session:execute"],
      lease_fields: ["auth_json"],
      now: now
    }
  end

  defp lease_context(account, now) do
    %{
      tenant_id: account.tenant_id,
      actor_id: "operator-1",
      required_scopes: ["session:execute"],
      ttl_seconds: 60,
      now: now,
      provider_family: account.provider_family,
      provider_account_ref: account.account_ref,
      connector_instance_ref: "connector-instance://codex/developer",
      credential_handle_ref: account.credential_handle_ref,
      operation_class: "cli",
      execution_context_ref: "execution-context://codex/test/1",
      target_ref: "target://local/codex/test",
      attach_grant_ref: "attach-grant://codex/test/1",
      operation_policy_ref: "operation-policy://codex/session-turn/1",
      policy_revision_ref: "policy-revision://codex/session-turn/1",
      target_grant_revision: "target-grant-revision://codex/test/1",
      rotation_epoch: account.generation,
      fence_token: "#{account.account_ref}:fence:#{account.fence}",
      authority_ref: "citadel://grant/codex/test/1",
      authority_decision_ref: "citadel://decision/codex/test/1",
      authority_scope: ["session:execute"],
      installation_revision: "installation://nshkr/developer-local/1",
      effect_ref: "effect://codex/test/1",
      operation_ref: "operation://codex/session-turn/test/1",
      endpoint_ref: account.endpoint_ref,
      max_calls: 1,
      max_tokens: 1024,
      allowed_models: ["codex-default"],
      network_policy: :provider_only
    }
  end

  defp managed_invoke_opts(lease, request, lease_context, now, workspace_root) do
    [
      credential_lease: lease,
      materialization_request: request,
      materialization_context: %{
        tenant_id: lease_context.tenant_id,
        provider_family: lease_context.provider_family,
        connector_instance_ref: lease_context.connector_instance_ref,
        provider_account_ref: lease_context.provider_account_ref,
        credential_handle_ref: lease_context.credential_handle_ref,
        operation_class: lease_context.operation_class,
        target_ref: lease_context.target_ref,
        attach_grant_ref: lease_context.attach_grant_ref,
        operation_policy_ref: lease_context.operation_policy_ref,
        current_policy_revision_ref: lease_context.policy_revision_ref,
        current_rotation_epoch: lease_context.rotation_epoch,
        current_target_grant_revision: lease_context.target_grant_revision,
        fence_token: lease_context.fence_token,
        current_installation_revision: lease_context.installation_revision,
        requested_authority_scope: lease_context.authority_scope,
        requested_model: "codex-default",
        requested_tokens: 256,
        network_target: :provider,
        now: DateTime.add(now, 1, :second)
      },
      workspace_root: workspace_root,
      workspace_ref: "workspace://tenant-1/codex/test",
      managed_session_ref: "managed-session://codex/test/1",
      managed_session_generation: 1,
      operation_policy_ref: lease_context.operation_policy_ref,
      authority_decision_ref: lease_context.authority_decision_ref,
      actor_id: "operator-1",
      tenant_id: "tenant-1",
      environment: :prod,
      trace_id: "trace-managed-codex-test",
      run_id: "jido-run://managed-codex/test/1",
      cost_meter_ref: "meter://managed-codex-test",
      budget_refs: ["budget://managed-codex-test/per-run"],
      allowed_operations: ["codex.session.turn"],
      sandbox: %{
        level: :strict,
        egress: :restricted,
        approvals: :manual,
        file_scope: workspace_root,
        allowed_tools: ["codex.session.turn"]
      }
    ]
  end
end
