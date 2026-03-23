defmodule Jido.Integration.V2.Apps.DevopsIncidentResponse do
  @moduledoc """
  Thin proof app that composes install provisioning, hosted webhook routing,
  async dispatch, replay, and restart recovery into one recoverable workflow.
  """

  alias Jido.Integration.TestTmpDir
  alias Jido.Integration.V2, as: V2
  alias Jido.Integration.V2.Apps.DevopsIncidentResponse.ExecuteTriggerHandler
  alias Jido.Integration.V2.Apps.DevopsIncidentResponse.GitHubIssueConnector
  alias Jido.Integration.V2.DispatchRuntime
  alias Jido.Integration.V2.DispatchRuntime.Dispatch
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.StoreLocal
  alias Jido.Integration.V2.WebhookRouter
  alias Jido.Integration.V2.WebhookRouter.Route

  @wait_poll_ms 25
  @default_wait_attempts 200

  @type install_view :: %{
          install: Jido.Integration.V2.Auth.Install.t(),
          connection: Jido.Integration.V2.Auth.Connection.t(),
          credential_ref: Jido.Integration.V2.CredentialRef.t(),
          route: Route.t(),
          webhook_secret: String.t()
        }

  @type runtime :: %{
          runtime_root: String.t(),
          store_local_dir: String.t(),
          dispatch_dir: String.t(),
          router_dir: String.t(),
          dispatch_runtime: pid(),
          webhook_router: pid(),
          max_attempts: pos_integer(),
          backoff_base_ms: pos_integer(),
          backoff_cap_ms: pos_integer()
        }

  @spec boot(map()) :: {:ok, runtime()}
  def boot(opts \\ %{}) when is_map(opts) do
    runtime_root =
      opts
      |> Map.get(:runtime_root, default_runtime_root())
      |> Path.expand()

    store_local_dir = Path.join(runtime_root, "store_local")
    dispatch_dir = Path.join(runtime_root, "dispatch_runtime")
    router_dir = Path.join(runtime_root, "webhook_router")

    File.mkdir_p!(store_local_dir)
    File.mkdir_p!(dispatch_dir)
    File.mkdir_p!(router_dir)

    :ok = configure_local_durability!(store_local_dir)
    :ok = ensure_application_started!(:telemetry)
    :ok = V2.register_connector(GitHubIssueConnector)

    max_attempts = Map.get(opts, :max_attempts, 2)
    backoff_base_ms = Map.get(opts, :backoff_base_ms, 25)
    backoff_cap_ms = Map.get(opts, :backoff_cap_ms, 100)

    with {:ok, dispatch_runtime} <-
           start_dispatch_runtime(dispatch_dir,
             max_attempts: max_attempts,
             backoff_base_ms: backoff_base_ms,
             backoff_cap_ms: backoff_cap_ms
           ),
         :ok <-
           DispatchRuntime.register_handler(
             dispatch_runtime,
             GitHubIssueConnector.trigger_id(),
             ExecuteTriggerHandler
           ),
         {:ok, webhook_router} <- WebhookRouter.start_link(name: nil, storage_dir: router_dir) do
      {:ok,
       %{
         runtime_root: runtime_root,
         store_local_dir: store_local_dir,
         dispatch_dir: dispatch_dir,
         router_dir: router_dir,
         dispatch_runtime: dispatch_runtime,
         webhook_router: webhook_router,
         max_attempts: max_attempts,
         backoff_base_ms: backoff_base_ms,
         backoff_cap_ms: backoff_cap_ms
       }}
    end
  end

  @spec stop(runtime()) :: :ok
  def stop(runtime) when is_map(runtime) do
    stop_process(Map.get(runtime, :webhook_router))
    stop_process(Map.get(runtime, :dispatch_runtime))
    :ok
  end

  @spec provision_install(runtime(), map()) :: {:ok, install_view()} | {:error, term()}
  def provision_install(runtime, attrs \\ %{}) when is_map(runtime) and is_map(attrs) do
    tenant_id = Map.get(attrs, :tenant_id, "tenant-devops")
    actor_id = Map.get(attrs, :actor_id, "pager-operator")
    subject = Map.get(attrs, :subject, "octocat")
    requested_scopes = Map.get(attrs, :requested_scopes, ["repo"])
    granted_scopes = Map.get(attrs, :granted_scopes, requested_scopes)
    webhook_secret = Map.get(attrs, :webhook_secret, "devops-incident-secret")
    now = Map.get(attrs, :now, ~U[2026-03-12 12:00:00Z])

    with {:ok, %{install: install, connection: connection}} <-
           V2.start_install(GitHubIssueConnector.connector_id(), tenant_id, %{
             actor_id: actor_id,
             auth_type: :oauth2,
             subject: subject,
             requested_scopes: requested_scopes,
             now: now
           }),
         {:ok,
          %{credential_ref: credential_ref, install: completed_install, connection: connected}} <-
           V2.complete_install(install.install_id, %{
             actor_id: actor_id,
             subject: subject,
             granted_scopes: granted_scopes,
             secret: %{
               access_token: "gho-demo-token",
               webhook_secret: webhook_secret
             },
             now: now
           }),
         {:ok, route} <-
           WebhookRouter.register_route(
             runtime.webhook_router,
             GitHubIssueConnector.route_attrs(%{
               tenant_id: tenant_id,
               connection_id: connection.connection_id,
               install_id: install.install_id,
               credential_ref: credential_ref
             })
           ) do
      {:ok,
       %{
         install: completed_install,
         connection: connected,
         credential_ref: credential_ref,
         route: route,
         webhook_secret: webhook_secret
       }}
    end
  end

  @spec fetch_route(runtime(), String.t()) :: {:ok, Route.t()} | :error
  def fetch_route(runtime, route_id) when is_map(runtime) and is_binary(route_id) do
    WebhookRouter.fetch_route(runtime.webhook_router, route_id)
  end

  @spec ingest_issue_webhook(runtime(), install_view(), map(), keyword()) ::
          WebhookRouter.webhook_result()
  def ingest_issue_webhook(runtime, install, body, opts \\ [])
      when is_map(runtime) and is_map(install) and is_map(body) do
    request =
      build_request(
        install.install.install_id,
        install.webhook_secret,
        body,
        Keyword.get(opts, :delivery_id, default_delivery_id()),
        Keyword.get(opts, :external_id)
      )

    WebhookRouter.route_webhook(
      runtime.webhook_router,
      request,
      dispatch_runtime: runtime.dispatch_runtime
    )
  end

  @spec replay_dispatch(runtime(), String.t()) :: {:ok, Dispatch.t()} | {:error, term()}
  def replay_dispatch(runtime, dispatch_id) when is_map(runtime) and is_binary(dispatch_id) do
    DispatchRuntime.replay(runtime.dispatch_runtime, dispatch_id)
  end

  @spec restart_dispatch_runtime(runtime()) :: runtime()
  def restart_dispatch_runtime(runtime) when is_map(runtime) do
    stop_process(runtime.dispatch_runtime)

    {:ok, dispatch_runtime} =
      start_dispatch_runtime(runtime.dispatch_dir,
        max_attempts: runtime.max_attempts,
        backoff_base_ms: runtime.backoff_base_ms,
        backoff_cap_ms: runtime.backoff_cap_ms
      )

    :ok =
      DispatchRuntime.register_handler(
        dispatch_runtime,
        GitHubIssueConnector.trigger_id(),
        ExecuteTriggerHandler
      )

    %{runtime | dispatch_runtime: dispatch_runtime}
  end

  @spec wait_for_dispatch(runtime(), String.t(), (Dispatch.t() -> boolean()), non_neg_integer()) ::
          Dispatch.t()
  def wait_for_dispatch(runtime, dispatch_id, predicate, attempts \\ @default_wait_attempts)
      when is_map(runtime) and is_binary(dispatch_id) and is_function(predicate, 1) do
    do_wait_for_dispatch(runtime.dispatch_runtime, dispatch_id, predicate, attempts, :missing)
  end

  @spec wait_for_run(runtime(), String.t(), (Run.t() -> boolean()), non_neg_integer()) :: Run.t()
  def wait_for_run(_runtime, run_id, predicate, attempts \\ @default_wait_attempts)
      when is_binary(run_id) and is_function(predicate, 1) do
    do_wait_for_run(run_id, predicate, attempts, :missing)
  end

  defp do_wait_for_dispatch(_dispatch_runtime, dispatch_id, _predicate, 0, last_seen) do
    raise "dispatch #{dispatch_id} did not reach the expected state; last seen: #{inspect(last_seen)}"
  end

  defp do_wait_for_dispatch(dispatch_runtime, dispatch_id, predicate, attempts, _last_seen) do
    case DispatchRuntime.fetch_dispatch(dispatch_runtime, dispatch_id) do
      {:ok, %Dispatch{} = dispatch} ->
        if predicate.(dispatch) do
          dispatch
        else
          Process.sleep(@wait_poll_ms)

          do_wait_for_dispatch(
            dispatch_runtime,
            dispatch_id,
            predicate,
            attempts - 1,
            dispatch.status
          )
        end

      :error ->
        Process.sleep(@wait_poll_ms)
        do_wait_for_dispatch(dispatch_runtime, dispatch_id, predicate, attempts - 1, :missing)
    end
  end

  defp do_wait_for_run(run_id, _predicate, 0, last_seen) do
    raise "run #{run_id} did not reach the expected state; last seen: #{inspect(last_seen)}"
  end

  defp do_wait_for_run(run_id, predicate, attempts, _last_seen) do
    case V2.fetch_run(run_id) do
      {:ok, %Run{} = run} ->
        if predicate.(run) do
          run
        else
          Process.sleep(@wait_poll_ms)
          do_wait_for_run(run_id, predicate, attempts - 1, run.status)
        end

      :error ->
        Process.sleep(@wait_poll_ms)
        do_wait_for_run(run_id, predicate, attempts - 1, :missing)
    end
  end

  defp configure_local_durability!(store_local_dir) do
    StoreLocal.configure_defaults!(storage_dir: store_local_dir)
    restart_store_local!()
    :ok
  end

  defp restart_store_local! do
    case Application.stop(:jido_integration_v2_store_local) do
      :ok -> :ok
      {:error, {:not_started, :jido_integration_v2_store_local}} -> :ok
    end

    stop_named_supervisor(Jido.Integration.V2.StoreLocal.Application)
    ensure_application_started!(:jido_integration_v2_store_local)
    :ok
  end

  defp ensure_application_started!(app) do
    case Application.ensure_all_started(app) do
      {:ok, _started} ->
        :ok

      {:error, {failed_app, reason}} ->
        if missing_app_spec?(reason) do
          start_application_fallback!(failed_app)
        else
          raise "failed to start #{inspect(failed_app)}: #{inspect(reason)}"
        end
    end
  end

  defp start_dispatch_runtime(storage_dir, opts) do
    DispatchRuntime.start_link(
      Keyword.merge(
        [
          name: nil,
          storage_dir: storage_dir
        ],
        opts
      )
    )
  end

  defp build_request(install_id, webhook_secret, body, delivery_id, external_id) do
    raw_body = inspect(body)

    headers = %{
      "x-github-delivery" => delivery_id,
      "x-hub-signature-256" => signature(webhook_secret, raw_body)
    }

    request = %{
      install_id: install_id,
      raw_body: raw_body,
      body: body,
      headers: headers
    }

    if is_binary(external_id) and byte_size(String.trim(external_id)) > 0 do
      Map.put(request, :external_id, external_id)
    else
      request
    end
  end

  defp signature(secret, raw_body) do
    "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, secret, raw_body), case: :lower)
  end

  defp stop_process(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      ref = Process.monitor(pid)
      Process.unlink(pid)
      GenServer.stop(pid, :shutdown, 5_000)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        5_000 -> raise "process #{inspect(pid)} did not terminate"
      end
    else
      :ok
    end
  end

  defp stop_process(_pid), do: :ok

  defp stop_named_supervisor(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> stop_process(pid)
    end
  end

  defp missing_app_spec?({:bad_name, _path}), do: true

  defp missing_app_spec?({message, path})
       when is_list(message) and is_list(path) do
    to_string(message) == "no such file or directory" and
      String.ends_with?(to_string(path), ".app")
  end

  defp missing_app_spec?(_reason), do: false

  defp start_application_fallback!(:jido_integration_v2_store_local) do
    ensure_supervisor_started!(
      [Jido.Integration.V2.ControlPlane.Registry, Jido.Integration.V2.ControlPlane.RunLedger],
      Jido.Integration.V2.ControlPlane.Supervisor,
      Jido.Integration.V2.ControlPlane.Application
    )

    ensure_supervisor_started!(
      [Jido.Integration.V2.Auth.Store],
      Jido.Integration.V2.Auth.Supervisor,
      Jido.Integration.V2.Auth.Application
    )

    ensure_supervisor_started!(
      [Jido.Integration.V2.StoreLocal.Server],
      Jido.Integration.V2.StoreLocal.Application,
      Jido.Integration.V2.StoreLocal.Application
    )
  end

  defp start_application_fallback!(app) do
    raise "failed to start #{inspect(app)}: application spec is unavailable"
  end

  defp ensure_supervisor_started!(required_processes, supervisor_name, application_module) do
    if Enum.all?(required_processes, &Process.whereis/1) do
      :ok
    else
      stop_named_supervisor(supervisor_name)

      case application_module.start(:normal, []) do
        {:ok, _pid} ->
          :ok

        {:error, {:already_started, _pid}} ->
          :ok

        {:error, reason} ->
          raise "failed to start #{inspect(supervisor_name)}: #{inspect(reason)}"
      end
    end
  end

  defp default_runtime_root do
    TestTmpDir.create!("jido_devops_incident_response")
  end

  defp default_delivery_id do
    "delivery-#{System.unique_integer([:positive])}"
  end
end
