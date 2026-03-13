defmodule Jido.Integration.Examples.GitHubIntegration do
  @moduledoc """
  Live GitHub integration example — demonstrates every feature of
  jido_integration using real GitHub API calls.

  ## Prerequisites

      # Authenticate with GitHub CLI
      gh auth login

      # For write operations, set a test repo you own:
      export GITHUB_TEST_OWNER=your-username
      export GITHUB_TEST_REPO=your-test-repo

  ## Running

      cd packages/connectors/github

      # Read-only demo (lists issues from elixir-lang/elixir):
      MIX_ENV=test mix run -e "Jido.Integration.Examples.GitHubIntegration.run_read_only()"

      # Full demo (creates, fetches, updates, labels, comments on, and closes
      # a test issue on your repo):
      GITHUB_TEST_OWNER=nshkrdotcom GITHUB_TEST_REPO=test \\
        MIX_ENV=test mix run -e "Jido.Integration.Examples.GitHubIntegration.run_all()"

  No mocks. No fakes. Real HTTP via Req, real tokens, real GenServers.

  The example talks directly to `Auth.Server` because the server is the
  canonical auth engine. A production host would put `Auth.Bridge` around these
  same runtime calls for HTTP routing and tenancy resolution.
  """

  alias Jido.Integration.Auth.{Credential, Server}
  alias Jido.Integration.Connectors.GitHub
  alias Jido.Integration.Dispatch.Consumer
  alias Jido.Integration.Operation
  alias Jido.Integration.Webhook.{Dedupe, Ingress, Router}

  @default_read_owner "elixir-lang"
  @default_read_repo "elixir"

  # ── Config ──────────────────────────────────────────────────────────

  @doc """
  Resolve a GitHub token from GITHUB_TOKEN env var or `gh auth token`.
  Raises if neither is available.
  """
  def resolve_token! do
    case System.get_env("GITHUB_TOKEN") do
      token when is_binary(token) and token != "" ->
        token

      _ ->
        case System.cmd("gh", ["auth", "token"], stderr_to_stdout: true) do
          {token, 0} -> String.trim(token)
          _ -> raise "No GitHub token. Set GITHUB_TOKEN or run `gh auth login`."
        end
    end
  end

  @doc """
  Resolve write target repo from GITHUB_TEST_OWNER / GITHUB_TEST_REPO.
  """
  def resolve_write_repo! do
    owner =
      System.get_env("GITHUB_TEST_OWNER") ||
        raise "Set GITHUB_TEST_OWNER (e.g. export GITHUB_TEST_OWNER=your-username)"

    repo =
      System.get_env("GITHUB_TEST_REPO") ||
        raise "Set GITHUB_TEST_REPO (e.g. export GITHUB_TEST_REPO=test)"

    {owner, repo}
  end

  # ── Infrastructure ──────────────────────────────────────────────────

  @doc """
  Boot Auth.Server, Webhook.Router, Webhook.Dedupe and resolve a real token.
  Ensures the real HTTP client (DefaultClient / Req) is active.

  `Auth.Server` uses the runtime's disk-backed store adapters by default, so
  install sessions, connections, and credentials survive a local server
  restart in the same working directory.
  """
  def setup_infrastructure do
    Application.put_env(:jido_integration_github, GitHub,
      http_client: Jido.Integration.Connectors.GitHub.DefaultClient
    )

    {:ok, auth} = Server.start_link(name: nil)
    {:ok, router} = Router.start_link(name: nil)
    {:ok, dedupe} = Dedupe.start_link(name: nil, ttl_ms: 60_000)
    {:ok, dispatch_consumer} = Consumer.start_link(name: nil)

    :ok =
      Consumer.register_callback(
        dispatch_consumer,
        "github.webhook.push",
        Jido.Integration.Examples.GitHubWebhookHandler
      )

    token = resolve_token!()

    %{
      auth: auth,
      router: router,
      dedupe: dedupe,
      dispatch_consumer: dispatch_consumer,
      token: token
    }
  end

  # ── OAuth Install Flow ─────────────────────────────────────────────

  @doc """
  Execute the OAuth install flow, storing a real GitHub token.

  In production the token arrives via GitHub's OAuth callback.
  Here we feed a real PAT through the same Auth.Server state machine,
  exercising identical state transitions that a host bridge would expose. The
  returned `session_state` is the opaque host callback payload for a durable
  install-session record, and the callback remains single-use.
  """
  def install_github(infra, tenant_id \\ "live-demo") do
    {:ok, install} =
      Server.start_install(infra.auth, "github", tenant_id,
        scopes: ["repo", "read:org"],
        actor_id: "admin@example.com",
        auth_base_url: "https://github.com/login/oauth/authorize"
      )

    {:ok, result} =
      Server.handle_callback(
        infra.auth,
        "github",
        %{
          "state" => install.session_state["state"],
          "credential" => %{
            access_token: infra.token,
            expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
          },
          "granted_scopes" => ["repo", "read:org"],
          "actor_id" => "system:oauth_callback"
        },
        install.session_state
      )

    {:ok, conn} = Server.get_connection(infra.auth, result.connection_id)

    %{
      connection_id: result.connection_id,
      auth_ref: result.auth_ref,
      connection_state: result.state,
      auth_url: install.auth_url,
      scopes: conn.scopes,
      revision: conn.revision,
      audit_trail_length: length(conn.actor_trail)
    }
  end

  # ── Operations ─────────────────────────────────────────────────────

  @doc """
  List issues from a real GitHub repository through the control plane.
  Default target: elixir-lang/elixir (public, always has issues).
  """
  def list_issues(infra, install_result, owner \\ @default_read_owner, repo \\ @default_read_repo) do
    envelope =
      Operation.Envelope.new("github.list_issues", %{
        "owner" => owner,
        "repo" => repo,
        "per_page" => 5
      })

    Jido.Integration.execute(GitHub, envelope,
      auth_server: infra.auth,
      connection_id: install_result.connection_id,
      auth_ref: install_result.auth_ref
    )
  end

  @doc """
  Create a real issue on a repository you own.
  """
  def create_issue(infra, install_result, owner, repo) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    envelope =
      Operation.Envelope.new("github.create_issue", %{
        "owner" => owner,
        "repo" => repo,
        "title" => "[jido-integration-test] Live example — #{timestamp}",
        "body" =>
          "Created by the jido_integration GitHub live example.\n" <>
            "Will be closed automatically. Safe to delete.\n\n" <>
            "Timestamp: #{timestamp}"
      })

    Jido.Integration.execute(GitHub, envelope,
      auth_server: infra.auth,
      connection_id: install_result.connection_id,
      auth_ref: install_result.auth_ref
    )
  end

  @doc """
  Fetch a single issue from GitHub.
  """
  def fetch_issue(infra, install_result, owner, repo, issue_number) do
    envelope =
      Operation.Envelope.new("github.fetch_issue", %{
        "owner" => owner,
        "repo" => repo,
        "issue_number" => issue_number
      })

    Jido.Integration.execute(GitHub, envelope,
      auth_server: infra.auth,
      connection_id: install_result.connection_id,
      auth_ref: install_result.auth_ref
    )
  end

  @doc """
  Create a real comment on a GitHub issue.
  """
  def create_comment(infra, install_result, owner, repo, issue_number) do
    envelope =
      Operation.Envelope.new("github.create_comment", %{
        "owner" => owner,
        "repo" => repo,
        "issue_number" => issue_number,
        "body" =>
          "Comment from jido_integration live example.\n\n" <>
            "Verifying the full control-plane → adapter → GitHub API pipeline end-to-end."
      })

    Jido.Integration.execute(GitHub, envelope,
      auth_server: infra.auth,
      connection_id: install_result.connection_id,
      auth_ref: install_result.auth_ref
    )
  end

  @doc """
  Update a GitHub issue.
  """
  def update_issue(infra, install_result, owner, repo, issue_number, attrs) do
    envelope =
      Operation.Envelope.new(
        "github.update_issue",
        Map.merge(
          %{"owner" => owner, "repo" => repo, "issue_number" => issue_number},
          attrs
        )
      )

    Jido.Integration.execute(GitHub, envelope,
      auth_server: infra.auth,
      connection_id: install_result.connection_id,
      auth_ref: install_result.auth_ref
    )
  end

  @doc """
  Add labels to an issue.
  """
  def label_issue(infra, install_result, owner, repo, issue_number, labels) do
    envelope =
      Operation.Envelope.new("github.label_issue", %{
        "owner" => owner,
        "repo" => repo,
        "issue_number" => issue_number,
        "labels" => labels
      })

    Jido.Integration.execute(GitHub, envelope,
      auth_server: infra.auth,
      connection_id: install_result.connection_id,
      auth_ref: install_result.auth_ref
    )
  end

  @doc """
  Update a comment on an issue.
  """
  def update_comment(infra, install_result, owner, repo, comment_id, body) do
    envelope =
      Operation.Envelope.new("github.update_comment", %{
        "owner" => owner,
        "repo" => repo,
        "comment_id" => comment_id,
        "body" => body
      })

    Jido.Integration.execute(GitHub, envelope,
      auth_server: infra.auth,
      connection_id: install_result.connection_id,
      auth_ref: install_result.auth_ref
    )
  end

  @doc """
  Close a GitHub issue through the connector operation.
  """
  def close_issue(infra, install_result, owner, repo, issue_number) do
    envelope =
      Operation.Envelope.new("github.close_issue", %{
        "owner" => owner,
        "repo" => repo,
        "issue_number" => issue_number
      })

    Jido.Integration.execute(GitHub, envelope,
      auth_server: infra.auth,
      connection_id: install_result.connection_id,
      auth_ref: install_result.auth_ref
    )
  end

  # ── Scope Enforcement ──────────────────────────────────────────────

  @doc """
  Demonstrate scope enforcement — a connection with only "read:org" scope
  cannot execute operations requiring "repo" scope.

  The Auth.Server rejects before any HTTP call is made.
  """
  def test_scope_enforcement(infra) do
    {:ok, install} =
      Server.start_install(infra.auth, "github", "read-only-tenant",
        scopes: ["read:org"],
        actor_id: "user@readonly.com"
      )

    {:ok, result} =
      Server.handle_callback(
        infra.auth,
        "github",
        %{
          "state" => install.session_state["state"],
          "credential" => %{
            access_token: infra.token,
            expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
          },
          "granted_scopes" => ["read:org"]
        },
        install.session_state
      )

    envelope =
      Operation.Envelope.new("github.list_issues", %{
        "owner" => @default_read_owner,
        "repo" => @default_read_repo
      })

    {:error, error} =
      Jido.Integration.execute(GitHub, envelope,
        auth_server: infra.auth,
        connection_id: result.connection_id,
        auth_ref: result.auth_ref
      )

    %{
      error_class: error.class,
      error_code: error.code,
      error_message: error.message
    }
  end

  # ── Blocked State ──────────────────────────────────────────────────

  @doc """
  Demonstrate blocked state rejection — a connection in :reauth_required
  cannot execute operations. The control plane rejects before any API call.
  """
  def test_blocked_state(infra, install_result) do
    {:ok, _} =
      Server.transition_connection(
        infra.auth,
        install_result.connection_id,
        :reauth_required,
        "system:scope_downgrade"
      )

    envelope =
      Operation.Envelope.new("github.list_issues", %{
        "owner" => @default_read_owner,
        "repo" => @default_read_repo
      })

    {:error, error} =
      Jido.Integration.execute(GitHub, envelope,
        auth_server: infra.auth,
        connection_id: install_result.connection_id,
        auth_ref: install_result.auth_ref
      )

    # Restore connection for subsequent demos
    {:ok, _} =
      Server.transition_connection(
        infra.auth,
        install_result.connection_id,
        :installing,
        "admin@example.com"
      )

    {:ok, _} =
      Server.transition_connection(
        infra.auth,
        install_result.connection_id,
        :connected,
        "system:reinstall"
      )

    %{
      error_class: error.class,
      error_code: error.code,
      blocked_state: "reauth_required"
    }
  end

  # ── Webhook Ingress ────────────────────────────────────────────────

  @doc """
  Full webhook ingress pipeline: route -> HMAC verify -> dedupe -> dispatch.

  Uses real HMAC-SHA256 verification with a real secret and the real
  Router/Ingress/Dedupe GenServers. The payload is constructed locally
  (receiving live webhooks from GitHub requires a public endpoint —
  use ngrok or smee.io for that).
  """
  def webhook_ingress(infra) do
    webhook_secret = "whsec_live_#{:crypto.strong_rand_bytes(16) |> Base.encode16()}"

    {:ok, webhook_cred} = Credential.new(%{type: :webhook_secret, key: webhook_secret})

    {:ok, secret_ref} =
      Server.store_credential(infra.auth, "github", "live-demo-webhook", webhook_cred)

    :ok =
      Router.register_route(infra.router, %{
        connector_id: "github",
        tenant_id: "live-demo",
        connection_id: "conn_webhook_live",
        install_id: "gh_install_live",
        trigger_id: "github.webhook.push",
        callback_topology: :dynamic_per_install,
        verification: %{
          type: :hmac,
          algorithm: :sha256,
          header: "x-hub-signature-256",
          secret_ref: secret_ref
        }
      })

    # Realistic webhook payload (same structure GitHub sends)
    issue_body =
      Jason.encode!(%{
        "action" => "opened",
        "issue" => %{
          "number" => 42,
          "title" => "Live webhook ingress test",
          "user" => %{"login" => "jido-integration"}
        },
        "repository" => %{"full_name" => "test/webhook-demo"}
      })

    issue_request =
      build_webhook_request(
        "gh_install_live",
        issue_body,
        webhook_secret,
        "issues",
        "delivery_live_001"
      )

    {:ok, issue_result} =
      Ingress.process(issue_request,
        router: infra.router,
        dedupe: infra.dedupe,
        auth_server: infra.auth,
        dispatch_consumer: infra.dispatch_consumer,
        adapter: GitHub
      )

    issue_run =
      wait_for_run(infra.dispatch_consumer, issue_result["run_id"], &(&1.status == :succeeded))

    # Dedupe rejects the duplicate
    duplicate_result =
      Ingress.process(issue_request,
        router: infra.router,
        dedupe: infra.dedupe,
        auth_server: infra.auth,
        dispatch_consumer: infra.dispatch_consumer,
        adapter: GitHub
      )

    # HMAC rejects tampered payload
    tampered_request = %{
      issue_request
      | raw_body: "tampered_body",
        headers: Map.put(issue_request.headers, "x-github-delivery", "delivery_tampered")
    }

    sig_failure_result =
      Ingress.process(tampered_request,
        router: infra.router,
        dedupe: infra.dedupe,
        auth_server: infra.auth,
        dispatch_consumer: infra.dispatch_consumer
      )

    # Unknown route is rejected
    unknown_request = %{
      issue_request
      | install_id: "unknown_install",
        headers: Map.put(issue_request.headers, "x-github-delivery", "delivery_unknown")
    }

    unknown_result =
      Ingress.process(unknown_request,
        router: infra.router,
        dedupe: infra.dedupe,
        auth_server: infra.auth,
        dispatch_consumer: infra.dispatch_consumer
      )

    %{
      issue_event: issue_run.result,
      duplicate_rejected: duplicate_result == {:error, :duplicate},
      signature_rejected: sig_failure_result == {:error, :signature_invalid},
      unknown_route_rejected: unknown_result == {:error, :route_not_found},
      routes_registered: length(Router.list_routes(infra.router))
    }
  end

  # ── Token Refresh ──────────────────────────────────────────────────

  @doc """
  Demonstrate token refresh mechanics via Auth.Server.

  Stores an expired credential, sets a refresh callback that returns
  the real token (in production this would call GitHub's OAuth token
  endpoint), and verifies the Auth.Server transparently refreshes.
  """
  def token_refresh(infra) do
    {:ok, cred} =
      Credential.new(%{
        type: :oauth2,
        access_token: "expired_placeholder",
        refresh_token: "refresh_placeholder",
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second),
        scopes: ["repo"]
      })

    {:ok, auth_ref} = Server.store_credential(infra.auth, "github", "refresh-demo", cred)

    # In production this calls GitHub's token endpoint.
    # Here we return the real token to verify the refresh pipeline.
    Server.set_refresh_callback(infra.auth, fn _ref, _refresh_token ->
      {:ok,
       %{
         access_token: infra.token,
         refresh_token: "refreshed_rt",
         expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
       }}
    end)

    {:ok, fresh} = Server.resolve_credential(infra.auth, auth_ref, %{connector_id: "github"})

    %{
      original_token: "expired_placeholder",
      refreshed_token: fresh.access_token,
      refresh_worked: fresh.access_token == infra.token,
      new_expiry: fresh.expires_at
    }
  end

  # ── Refresh Failure ────────────────────────────────────────────────

  @doc """
  Demonstrate refresh failure -> automatic :reauth_required transition.
  """
  def refresh_failure(infra) do
    {:ok, conn} = Server.create_connection(infra.auth, "github", "fail-demo")
    {:ok, _} = Server.transition_connection(infra.auth, conn.id, :installing, "user")
    {:ok, _} = Server.transition_connection(infra.auth, conn.id, :connected, "system")

    {:ok, cred} =
      Credential.new(%{
        type: :oauth2,
        access_token: "will_fail",
        refresh_token: "will_fail",
        expires_at: DateTime.add(DateTime.utc_now(), -60, :second)
      })

    {:ok, auth_ref} = Server.store_credential(infra.auth, "github", "fail-demo", cred)
    :ok = Server.link_connection(infra.auth, conn.id, auth_ref)

    Server.set_refresh_callback(infra.auth, fn _ref, _rt -> {:error, :invalid_grant} end)

    {:error, :refresh_failed} =
      Server.resolve_credential(infra.auth, auth_ref, %{connector_id: "github"})

    {:ok, updated} = Server.get_connection(infra.auth, conn.id)

    %{
      connection_state: updated.state,
      requires_reauth: updated.state == :reauth_required,
      audit_trail:
        Enum.map(updated.actor_trail, fn e ->
          "#{e.from_state} -> #{e.to_state} by #{e.actor_id}"
        end)
    }
  end

  # ── Credential Rotation ────────────────────────────────────────────

  @doc """
  Demonstrate credential rotation — replace a stored credential's token.
  Rotates from a stale token to the real live token.
  """
  def credential_rotation(infra) do
    {:ok, cred} =
      Credential.new(%{
        type: :oauth2,
        access_token: "old_token_to_rotate",
        refresh_token: "old_refresh",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        scopes: ["repo"]
      })

    {:ok, auth_ref} = Server.store_credential(infra.auth, "github", "rotate-demo", cred)
    {:ok, original} = Server.resolve_credential(infra.auth, auth_ref, %{connector_id: "github"})

    {:ok, new_cred} =
      Credential.new(%{
        type: :oauth2,
        access_token: infra.token,
        refresh_token: "rotated_refresh",
        expires_at: DateTime.add(DateTime.utc_now(), 7200, :second),
        scopes: ["repo", "read:org"]
      })

    :ok = Server.rotate_credential(infra.auth, auth_ref, new_cred)
    {:ok, rotated} = Server.resolve_credential(infra.auth, auth_ref, %{connector_id: "github"})

    %{
      old_token: original.access_token,
      new_token: rotated.access_token,
      rotation_worked: rotated.access_token == infra.token
    }
  end

  # ── Credential Revocation ──────────────────────────────────────────

  @doc """
  Demonstrate credential revocation — remove a credential entirely.
  """
  def credential_revocation(infra) do
    {:ok, cred} =
      Credential.new(%{
        type: :oauth2,
        access_token: infra.token,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
        scopes: ["repo"]
      })

    {:ok, auth_ref} = Server.store_credential(infra.auth, "github", "revoke-demo", cred)
    {:ok, _} = Server.resolve_credential(infra.auth, auth_ref, %{connector_id: "github"})
    :ok = Server.revoke_credential(infra.auth, auth_ref)

    resolve_result = Server.resolve_credential(infra.auth, auth_ref, %{connector_id: "github"})

    %{
      revoke_ok: true,
      resolve_after_revoke: resolve_result
    }
  end

  # ── Connection Degradation ─────────────────────────────────────────

  @doc """
  Demonstrate connection degradation via mark_rotation_overdue.
  """
  def connection_degradation(infra) do
    {:ok, conn} = Server.create_connection(infra.auth, "github", "degrade-demo")
    {:ok, _} = Server.transition_connection(infra.auth, conn.id, :installing, "user")
    {:ok, _} = Server.transition_connection(infra.auth, conn.id, :connected, "system")

    {:ok, degraded} = Server.mark_rotation_overdue(infra.auth, conn.id)

    {:ok, recovered} =
      Server.transition_connection(infra.auth, conn.id, :connected, "system:rotation_complete")

    %{
      degraded_state: degraded.state,
      recovered_state: recovered.state,
      degradation_worked: degraded.state == :degraded,
      recovery_worked: recovered.state == :connected
    }
  end

  # ── Connection Lifecycle ───────────────────────────────────────────

  @doc """
  Full connection lifecycle:
  new -> installing -> connected -> degraded -> reauth_required -> installing -> connected
  """
  def connection_lifecycle(infra) do
    {:ok, conn} =
      Server.create_connection(infra.auth, "github", "lifecycle-demo", scopes: ["repo"])

    {:ok, _} = Server.transition_connection(infra.auth, conn.id, :installing, "user")
    {:ok, connected} = Server.transition_connection(infra.auth, conn.id, :connected, "system")

    {:ok, degraded} = Server.mark_rotation_overdue(infra.auth, conn.id)

    {:ok, reauth} =
      Server.transition_connection(
        infra.auth,
        conn.id,
        :reauth_required,
        "system:scope_downgrade"
      )

    {:ok, reinstalling} =
      Server.transition_connection(infra.auth, conn.id, :installing, "admin@example.com")

    {:ok, reconnected} =
      Server.transition_connection(infra.auth, conn.id, :connected, "system:reinstall")

    {:ok, final_conn} = Server.get_connection(infra.auth, conn.id)

    %{
      initial_state: connected.state,
      degraded_state: degraded.state,
      reauth_state: reauth.state,
      reinstalling_state: reinstalling.state,
      reconnected_state: reconnected.state,
      final_revision: final_conn.revision,
      audit_trail:
        Enum.map(final_conn.actor_trail, fn e ->
          "#{e.from_state} -> #{e.to_state} by #{e.actor_id}"
        end)
    }
  end

  # ── Run All ────────────────────────────────────────────────────────

  @doc """
  Run read-only demos. Safe against any GitHub account.
  Lists real issues from elixir-lang/elixir.
  """
  def run_read_only do
    IO.puts("=== Jido Integration GitHub — Live Read-Only Demo ===\n")

    infra = setup_infrastructure()
    IO.puts("[ok] Infrastructure booted (Auth.Server, Webhook.Router, Dedupe)")

    install = install_github(infra)
    IO.puts("[ok] OAuth install flow: #{install.connection_state}")

    {:ok, list_result} = list_issues(infra, install)
    count = list_result.result["total_count"]
    IO.puts("[ok] Listed #{count} issues from #{@default_read_owner}/#{@default_read_repo}")

    scope = test_scope_enforcement(infra)
    IO.puts("[ok] Scope enforcement: #{scope.error_class} (#{scope.error_code})")

    blocked = test_blocked_state(infra, install)
    IO.puts("[ok] Blocked state: #{blocked.error_class} (#{blocked.error_code})")

    webhook = webhook_ingress(infra)

    IO.puts(
      "[ok] Webhook pipeline: dedupe=#{webhook.duplicate_rejected}, sig_check=#{webhook.signature_rejected}"
    )

    refresh = token_refresh(infra)
    IO.puts("[ok] Token refresh: #{refresh.refresh_worked}")

    fail = refresh_failure(infra)
    IO.puts("[ok] Refresh failure -> reauth: #{fail.requires_reauth}")

    rotation = credential_rotation(infra)
    IO.puts("[ok] Credential rotation: #{rotation.rotation_worked}")

    revocation = credential_revocation(infra)
    IO.puts("[ok] Credential revocation: #{revocation.revoke_ok}")

    degradation = connection_degradation(infra)

    IO.puts(
      "[ok] Degradation: #{degradation.degradation_worked}, recovery: #{degradation.recovery_worked}"
    )

    lifecycle = connection_lifecycle(infra)
    IO.puts("[ok] Lifecycle: #{length(lifecycle.audit_trail)} transitions")

    IO.puts("\n=== All read-only demos passed ===")

    %{
      install: install,
      list_issues: list_result,
      scope_enforcement: scope,
      blocked_state: blocked,
      webhook: webhook,
      token_refresh: refresh,
      refresh_failure: fail,
      credential_rotation: rotation,
      credential_revocation: revocation,
      connection_degradation: degradation,
      connection_lifecycle: lifecycle
    }
  end

  @doc """
  Run all demos including write operations.
  Requires GITHUB_TEST_OWNER and GITHUB_TEST_REPO env vars.
  Creates, fetches, updates, labels, comments on, and closes a test issue.
  """
  def run_all do
    read_result = run_read_only()

    IO.puts("\n=== Write Operations ===\n")

    {owner, repo} = resolve_write_repo!()
    infra = setup_infrastructure()
    install = install_github(infra, "write-demo")

    {:ok, issue} = create_issue(infra, install, owner, repo)
    issue_number = issue.result["number"]
    IO.puts("[ok] Created issue ##{issue_number} on #{owner}/#{repo}")

    {:ok, fetched} = fetch_issue(infra, install, owner, repo, issue_number)
    IO.puts("[ok] Fetched issue ##{fetched.result["number"]}")

    {:ok, labeled} = label_issue(infra, install, owner, repo, issue_number, ["jido-integration"])
    IO.puts("[ok] Added #{length(labeled.result["labels"])} labels to issue ##{issue_number}")

    {:ok, updated_issue} =
      update_issue(infra, install, owner, repo, issue_number, %{
        "body" => "Updated by the jido_integration live example."
      })

    IO.puts("[ok] Updated issue ##{updated_issue.result["number"]}")

    {:ok, comment} = create_comment(infra, install, owner, repo, issue_number)
    IO.puts("[ok] Added comment #{comment.result["id"]} to issue ##{issue_number}")

    {:ok, updated_comment} =
      update_comment(
        infra,
        install,
        owner,
        repo,
        comment.result["id"],
        "Updated by the jido_integration live example."
      )

    IO.puts("[ok] Updated comment #{updated_comment.result["id"]}")

    {:ok, closed} = close_issue(infra, install, owner, repo, issue_number)
    IO.puts("[ok] Closed issue ##{issue_number} (#{closed.result["state"]})")

    IO.puts("\n=== All demos passed (read + write) ===")

    Map.merge(read_result, %{
      create_issue: issue,
      fetch_issue: fetched,
      label_issue: labeled,
      update_issue: updated_issue,
      create_comment: comment,
      update_comment: updated_comment,
      close_issue: closed,
      write_repo: "#{owner}/#{repo}",
      issue_number: issue_number
    })
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp build_webhook_request(install_id, body, secret, event_type, delivery_id) do
    signature =
      "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower))

    %{
      install_id: install_id,
      headers: %{
        "x-hub-signature-256" => signature,
        "x-github-event" => event_type,
        "x-github-delivery" => delivery_id
      },
      raw_body: body,
      body: Jason.decode!(body)
    }
  end

  defp wait_for_run(consumer, run_id, predicate, attempts \\ 50)

  defp wait_for_run(_consumer, run_id, _predicate, 0) do
    raise "run #{run_id} did not reach expected state"
  end

  defp wait_for_run(consumer, run_id, predicate, attempts) do
    case Consumer.get_run(consumer, run_id) do
      {:ok, run} ->
        if predicate.(run) do
          run
        else
          Process.sleep(10)
          wait_for_run(consumer, run_id, predicate, attempts - 1)
        end

      {:error, :not_found} ->
        Process.sleep(10)
        wait_for_run(consumer, run_id, predicate, attempts - 1)
    end
  end
end

defmodule Jido.Integration.Examples.GitHubWebhookHandler do
  @moduledoc false

  alias Jido.Integration.Connectors.GitHub

  def handle_trigger(event, _context) when is_map(event) do
    GitHub.handle_trigger(event["trigger_id"], event["payload"])
  end
end
