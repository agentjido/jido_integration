defmodule DevopsIncidentResponse.Runtime do
  @moduledoc """
  Thin reference-app runtime for the incident-response proving slice.
  """

  alias Jido.Integration.Auth.{Credential, Server}
  alias Jido.Integration.Dispatch.Consumer
  alias Jido.Integration.Webhook.{Dedupe, Ingress, Router}

  @trigger_id "github.webhook.push"

  def boot(opts \\ []) do
    dir = Keyword.get(opts, :dir, Path.join(System.tmp_dir!(), "jido_integration_refapps"))
    prefix = Keyword.get(opts, :prefix, "devops_incident_response")
    max_attempts = Keyword.get(opts, :max_attempts, 2)

    {:ok, auth} =
      Server.start_link(
        name: nil,
        store_opts: [dir: dir, name: store_name(prefix, "credentials")],
        connection_store_opts: [dir: dir, name: store_name(prefix, "connections")]
      )

    {:ok, router} =
      Router.start_link(
        name: nil,
        store_opts: [dir: dir, name: store_name(prefix, "routes")]
      )

    {:ok, dedupe} =
      Dedupe.start_link(
        name: nil,
        ttl_ms: 60_000,
        store_opts: [dir: dir, name: store_name(prefix, "dedupe")]
      )

    consumer_opts = [
      name: nil,
      max_attempts: max_attempts,
      backoff_base_ms: 5,
      backoff_cap_ms: 25,
      dispatch_store_opts: [dir: dir, name: store_name(prefix, "dispatch")],
      run_store_opts: [dir: dir, name: store_name(prefix, "runs")]
    ]

    {:ok, consumer} = Consumer.start_link(consumer_opts)

    :ok =
      Consumer.register_callback(consumer, @trigger_id, DevopsIncidentResponse.GitHubIssueHandler)

    {:ok,
     %{
       auth: auth,
       router: router,
       dedupe: dedupe,
       consumer: consumer,
       consumer_opts: consumer_opts
     }}
  end

  def provision_install(runtime, opts \\ []) do
    tenant_id = Keyword.get(opts, :tenant_id, "acme")
    install_id = Keyword.get(opts, :install_id, "gh_install_1")
    webhook_secret = Keyword.get(opts, :webhook_secret, "devops_incident_secret")
    connection_id = Keyword.get(opts, :connection_id, "github_connection_1")

    {:ok, credential} = Credential.new(%{type: :webhook_secret, key: webhook_secret})
    {:ok, auth_ref} = Server.store_credential(runtime.auth, "github", tenant_id, credential)

    :ok =
      Router.register_route(runtime.router, %{
        connector_id: "github",
        tenant_id: tenant_id,
        connection_id: connection_id,
        install_id: install_id,
        trigger_id: @trigger_id,
        callback_topology: :dynamic_per_install,
        verification: %{
          type: :hmac,
          algorithm: :sha256,
          header: "x-hub-signature-256",
          secret_ref: auth_ref
        }
      })

    {:ok, %{tenant_id: tenant_id, install_id: install_id, webhook_secret: webhook_secret}}
  end

  def ingest_issue_webhook(runtime, install, body, opts \\ []) do
    request =
      build_request(
        install.install_id,
        body,
        install.webhook_secret,
        Keyword.get(opts, :event_type, "issues"),
        Keyword.get(opts, :delivery_id, "delivery_#{System.unique_integer([:positive])}")
      )

    Ingress.process(request,
      router: runtime.router,
      dedupe: runtime.dedupe,
      auth_server: runtime.auth,
      dispatch_consumer: runtime.consumer
    )
  end

  def replay(runtime, run_id) do
    Consumer.replay(runtime.consumer, run_id)
  end

  def restart_consumer(runtime) do
    ref = Process.monitor(runtime.consumer)
    Process.unlink(runtime.consumer)
    Process.exit(runtime.consumer, :kill)

    receive do
      {:DOWN, ^ref, :process, _, _} -> :ok
    after
      5_000 -> raise "consumer did not terminate"
    end

    {:ok, consumer} = Consumer.start_link(runtime.consumer_opts)

    :ok =
      Consumer.register_callback(consumer, @trigger_id, DevopsIncidentResponse.GitHubIssueHandler)

    %{runtime | consumer: consumer}
  end

  def wait_for_run(runtime, run_id, predicate, timeout_ms \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_run(runtime, run_id, predicate, deadline)
  end

  defp do_wait_for_run(runtime, run_id, predicate, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      raise "run #{run_id} did not reach expected state"
    end

    case Consumer.get_run(runtime.consumer, run_id) do
      {:ok, run} ->
        if predicate.(run) do
          run
        else
          Process.sleep(10)
          do_wait_for_run(runtime, run_id, predicate, deadline)
        end

      {:error, :not_found} ->
        Process.sleep(10)
        do_wait_for_run(runtime, run_id, predicate, deadline)
    end
  end

  defp build_request(install_id, body, secret, event_type, delivery_id) do
    raw_body = Jason.encode!(body)

    signature =
      "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower))

    %{
      install_id: install_id,
      headers: %{
        "x-hub-signature-256" => signature,
        "x-github-event" => event_type,
        "x-github-delivery" => delivery_id
      },
      raw_body: raw_body,
      body: body
    }
  end

  defp store_name(prefix, suffix), do: String.to_atom("#{prefix}_#{suffix}")
end
