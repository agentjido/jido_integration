defmodule Jido.Integration.V2.Connectors.GitHub.LiveSupport do
  @moduledoc false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.GitHub.ClientFactory
  alias Jido.Integration.V2.Connectors.GitHub.LiveEnv
  alias Jido.Integration.V2.Connectors.GitHub.LivePlan

  @runtime_apps [
    :jido_integration_v2_auth,
    :jido_integration_v2_control_plane,
    :jido_integration_v2_session_kernel,
    :jido_integration_v2_stream_runtime
  ]

  @spec run_auth_lifecycle!() :: map()
  def run_auth_lifecycle! do
    spec = prepare!(:auth)
    auth = install_connection!(spec)
    print_result!("auth lifecycle", auth_summary(auth))
  end

  @spec run_read_acceptance!() :: map()
  def run_read_acceptance! do
    spec = prepare!(:read)
    auth = install_connection!(spec)
    print_result!("read acceptance", perform_read_acceptance(auth, spec))
  end

  @spec run_write_acceptance!() :: map()
  def run_write_acceptance! do
    spec = prepare!(:write)
    auth = install_connection!(spec)
    print_result!("write acceptance", perform_write_acceptance(auth, spec))
  end

  @spec run_all_acceptance!() :: map()
  def run_all_acceptance! do
    spec = prepare!(:write)
    auth = install_connection!(spec)
    initial_list_result = list_issues!(auth, spec.repo)

    result =
      case LivePlan.all_read_target(spec, initial_list_result.output.issues) do
        {:existing, target} ->
          %{
            auth: auth_summary(auth),
            read:
              perform_read_acceptance(auth, spec,
                repo: target.repo,
                issue_number: target.issue_number,
                list_result: initial_list_result
              ),
            write: perform_write_acceptance(auth, spec),
            bootstrap: %{used?: false, source: target.source}
          }

        {:bootstrap, target} ->
          seed = write_seed()
          create_result = create_issue!(auth, target.repo, seed.title, seed.body)
          issue_number = create_result.output.issue_number

          try do
            %{
              auth: auth_summary(auth),
              read:
                perform_read_acceptance(auth, spec, repo: target.repo, issue_number: issue_number),
              write:
                perform_write_acceptance(auth, spec,
                  repo: target.repo,
                  seed: seed,
                  create_result: create_result,
                  issue_number: issue_number
                ),
              bootstrap: %{
                used?: true,
                reason: target.reason,
                requested_read_repo: spec.repo,
                effective_read_repo: target.repo,
                issue_number: issue_number
              }
            }
          rescue
            error ->
              safe_close_issue(auth, target.repo, issue_number)
              reraise(error, __STACKTRACE__)
          end
      end

    print_result!("full acceptance", result)
  end

  defp prepare!(mode) do
    env = System.get_env()

    case LiveEnv.validate(mode, env) do
      :ok ->
        :ok

      {:error, missing} ->
        raise ArgumentError,
              """
              missing live configuration for #{mode}: #{Enum.join(missing, ", ")}

              See connectors/github/docs/live_acceptance.md for the package-local runbook.
              """
    end

    spec = LiveEnv.spec(env)
    spec = Map.put(spec, :token, resolve_token!(spec))

    configure_live_provider!(spec)
    boot_runtime!()
    spec
  end

  defp resolve_token!(spec) do
    case spec.token do
      token when is_binary(token) and token != "" ->
        token

      _other ->
        executable = System.find_executable("gh")

        expect!(
          is_binary(executable),
          "missing GitHub token; set #{Enum.join(LiveEnv.preferred_token_envs(), " or ")} or install `gh auth login`"
        )

        case System.cmd(executable, ["auth", "token"], stderr_to_stdout: true) do
          {token, 0} ->
            token
            |> String.trim()
            |> tap(fn trimmed ->
              expect!(trimmed != "", "`gh auth token` returned an empty token")
            end)

          {output, _exit_code} ->
            raise ArgumentError,
                  "failed to resolve a GitHub token from gh: #{String.trim(output)}"
        end
    end
  end

  defp boot_runtime! do
    Enum.each(@runtime_apps, fn app ->
      case Application.ensure_all_started(app) do
        {:ok, _started} ->
          :ok

        {:error, {failed_app, reason}} ->
          raise "failed to start #{failed_app}: #{inspect(reason)}"
      end
    end)

    :ok = V2.reset!()
    :ok = V2.register_connector(GitHub)
  end

  defp configure_live_provider!(spec) do
    Application.put_env(:jido_integration_v2_github, ClientFactory, live_client_opts(spec))
  end

  defp live_client_opts(spec) do
    [transport: Pristine.Adapters.Transport.Finch]
    |> maybe_put(:base_url, spec.api_base_url)
    |> maybe_put(:timeout_ms, spec.timeout_ms)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp install_connection!(spec) do
    now = DateTime.utc_now()

    {:ok, %{install: install, connection: installing_connection}} =
      V2.start_install("github", spec.tenant_id, %{
        actor_id: spec.actor_id,
        auth_type: :oauth2,
        subject: spec.subject,
        requested_scopes: ["repo"],
        metadata: %{proof: "connectors/github live acceptance"},
        now: now
      })

    expect!(install.state == :installing, "install did not start in the installing state")

    expect!(
      installing_connection.state == :installing,
      "connection did not start in the installing state"
    )

    {:ok, %{install: completed_install, connection: connection, credential_ref: credential_ref}} =
      V2.complete_install(install.install_id, %{
        subject: spec.subject,
        granted_scopes: ["repo"],
        secret: %{access_token: spec.token},
        expires_at: nil,
        now: now
      })

    {:ok, fetched_install} = V2.fetch_install(install.install_id)
    {:ok, fetched_connection} = V2.connection_status(connection.connection_id)

    expect!(completed_install.state == :completed, "install did not complete")
    expect!(connection.state == :connected, "connection did not enter the connected state")

    expect!(
      fetched_install.state == :completed,
      "install fetch did not return durable completion truth"
    )

    expect!(
      fetched_connection.state == :connected,
      "connection status did not return durable connection truth"
    )

    {:ok, lease} =
      V2.request_lease(connection.connection_id, %{
        actor_id: spec.actor_id,
        required_scopes: ["repo"],
        ttl_seconds: 300,
        now: now
      })

    expect!(
      lease.payload == %{access_token: spec.token},
      "lease payload was not minimized to the access token"
    )

    expect!(lease.subject == spec.subject, "lease subject did not match the install subject")

    %{
      install: completed_install,
      connection: connection,
      credential_ref: credential_ref,
      lease: lease
    }
  end

  defp invoke!(auth, capability_id, input) do
    {:ok, capability} = V2.fetch_capability(capability_id)

    {:ok, result} =
      V2.invoke(capability_id, input,
        credential_ref: auth.credential_ref,
        actor_id: auth.connection.actor_id,
        tenant_id: auth.connection.tenant_id,
        environment: :prod,
        allowed_operations: [capability_id],
        sandbox: capability.metadata.policy.sandbox
      )

    refute_secret_leaks!(result, auth.lease.payload.access_token)
    refute_secret_leaks!(V2.events(result.run.run_id), auth.lease.payload.access_token)
    refute_secret_leaks!(V2.run_artifacts(result.run.run_id), auth.lease.payload.access_token)
    result
  end

  defp perform_read_acceptance(auth, spec, opts \\ []) do
    repo = Keyword.get(opts, :repo, spec.repo)
    list_result = Keyword.get(opts, :list_result) || list_issues!(auth, repo)

    issue_number =
      Keyword.get(opts, :issue_number) || spec.read_issue_number ||
        first_issue_number!(list_result.output.issues, repo)

    fetch_result = fetch_issue!(auth, repo, issue_number)

    expect!(list_result.output.repo == repo, "live issue list returned the wrong repo")
    expect!(fetch_result.output.repo == repo, "live issue fetch returned the wrong repo")

    expect!(
      fetch_result.output.issue_number == issue_number,
      "live issue fetch returned the wrong issue"
    )

    expect!(
      list_result.output.listed_by == spec.subject,
      "list result subject did not come from the lease"
    )

    expect!(
      fetch_result.output.fetched_by == spec.subject,
      "fetch result subject did not come from the lease"
    )

    %{
      repo: repo,
      listed_issue_count: list_result.output.total_count,
      fetched_issue_number: issue_number,
      auth_connection_id: auth.connection.connection_id,
      run_ids: [list_result.run.run_id, fetch_result.run.run_id]
    }
  end

  defp perform_write_acceptance(auth, spec, opts \\ []) do
    repo = Keyword.get(opts, :repo, spec.write_repo)
    seed = Keyword.get(opts, :seed, write_seed())

    create_result =
      Keyword.get(opts, :create_result) || create_issue!(auth, repo, seed.title, seed.body)

    issue_number = Keyword.get(opts, :issue_number) || create_result.output.issue_number

    try do
      fetch_result = fetch_issue!(auth, repo, issue_number)

      update_result =
        invoke!(auth, "github.issue.update", %{
          repo: repo,
          issue_number: issue_number,
          title: seed.title <> " [updated]",
          body: seed.body <> " Updated through the v2 platform boundary.",
          state: "open",
          labels: [spec.write_label],
          assignees: []
        })

      label_result =
        invoke!(auth, "github.issue.label", %{
          repo: repo,
          issue_number: issue_number,
          labels: [spec.write_label]
        })

      create_comment_result =
        invoke!(auth, "github.comment.create", %{
          repo: repo,
          issue_number: issue_number,
          body: seed.comment_body
        })

      update_comment_result =
        invoke!(auth, "github.comment.update", %{
          repo: repo,
          comment_id: create_comment_result.output.comment_id,
          body: seed.comment_body <> " [updated]"
        })

      close_result =
        invoke!(auth, "github.issue.close", %{
          repo: repo,
          issue_number: issue_number
        })

      expect!(create_result.output.repo == repo, "issue create returned the wrong repo")

      expect!(
        fetch_result.output.issue_number == issue_number,
        "issue fetch returned the wrong issue"
      )

      expect!(
        update_result.output.title == seed.title <> " [updated]",
        "issue update did not persist the title"
      )

      expect!(spec.write_label in label_result.output.labels, "issue label did not apply")

      expect!(
        create_comment_result.output.issue_number == issue_number,
        "comment create did not stay attached to the created issue"
      )

      expect!(
        update_comment_result.output.body == seed.comment_body <> " [updated]",
        "comment update did not persist"
      )

      expect!(
        close_result.output.state == "closed",
        "issue close did not return a closed state"
      )

      %{
        repo: repo,
        issue_number: issue_number,
        comment_id: create_comment_result.output.comment_id,
        label: spec.write_label,
        close_state: close_result.output.state,
        auth_connection_id: auth.connection.connection_id,
        run_ids: [
          create_result.run.run_id,
          fetch_result.run.run_id,
          update_result.run.run_id,
          label_result.run.run_id,
          create_comment_result.run.run_id,
          update_comment_result.run.run_id,
          close_result.run.run_id
        ]
      }
    rescue
      error ->
        safe_close_issue(auth, repo, issue_number)
        reraise(error, __STACKTRACE__)
    end
  end

  defp list_issues!(auth, repo) do
    invoke!(auth, "github.issue.list", %{
      repo: repo,
      state: "all",
      per_page: 5,
      page: 1
    })
  end

  defp fetch_issue!(auth, repo, issue_number) do
    invoke!(auth, "github.issue.fetch", %{
      repo: repo,
      issue_number: issue_number
    })
  end

  defp create_issue!(auth, repo, title, body) do
    invoke!(auth, "github.issue.create", %{
      repo: repo,
      title: title,
      body: body
    })
  end

  defp write_seed do
    marker = Integer.to_string(System.system_time(:second))

    %{
      title: "Jido live acceptance #{marker}",
      body: "Created by the package-local GitHub live proof harness.",
      comment_body: "Live proof comment #{marker}"
    }
  end

  defp safe_close_issue(auth, repo, issue_number)
       when is_binary(repo) and is_integer(issue_number) do
    _ =
      try do
        invoke!(auth, "github.issue.close", %{repo: repo, issue_number: issue_number})
      rescue
        _error -> :noop
      end

    :ok
  end

  defp safe_close_issue(_auth, _repo, _issue_number), do: :ok

  defp first_issue_number!([], repo) do
    raise ArgumentError,
          """
          the read-only proof needs a repo with at least one issue or #{LiveEnv.env_names().read_issue_number}
          set explicitly. Repo: #{repo}

          For the combined smoke run, `scripts/live_acceptance.sh all` can bootstrap a writable repo issue automatically.
          """
  end

  defp first_issue_number!([issue | _rest], _repo), do: issue.issue_number

  defp auth_summary(auth) do
    %{
      install_id: auth.install.install_id,
      connection_id: auth.connection.connection_id,
      credential_ref_id: auth.credential_ref.id,
      connection_state: auth.connection.state,
      granted_scopes: auth.connection.granted_scopes,
      lease_id: auth.lease.lease_id,
      lease_payload_keys: auth.lease.payload |> Map.keys() |> Enum.sort(),
      subject: auth.lease.subject
    }
  end

  defp refute_secret_leaks!(term, token) do
    expect!(
      not String.contains?(inspect(term), token),
      "live proof surfaced the raw GitHub token in runtime output"
    )
  end

  defp print_result!(label, result) do
    IO.puts("GitHub #{label} proof passed.")
    IO.inspect(result, label: "result")
    result
  end

  defp expect!(true, _message), do: :ok
  defp expect!(false, message), do: raise(ArgumentError, message)
end
