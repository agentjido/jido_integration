defmodule Jido.Integration.V2.Connectors.GitHub.LiveSupport do
  @moduledoc false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Connectors.GitHub
  alias Jido.Integration.V2.Connectors.GitHub.ClientFactory
  alias Jido.Integration.V2.Connectors.GitHub.InstallBinding
  alias Jido.Integration.V2.Connectors.GitHub.LivePlan
  alias Jido.Integration.V2.Connectors.GitHub.LiveSpec

  @runtime_apps [
    :jido_integration_v2_auth,
    :jido_integration_v2_control_plane
  ]

  @spec run_auth_lifecycle!([String.t()]) :: map()
  def run_auth_lifecycle!(argv \\ System.argv()) do
    spec = prepare!(:auth, argv)
    auth = install_connection!(spec)
    print_result!("auth lifecycle", auth_summary(auth))
  end

  @spec run_read_acceptance!([String.t()]) :: map()
  def run_read_acceptance!(argv \\ System.argv()) do
    spec = prepare!(:read, argv)
    auth = install_connection!(spec)
    print_result!("read acceptance", perform_read_acceptance(auth, spec))
  end

  @spec run_write_acceptance!([String.t()]) :: map()
  def run_write_acceptance!(argv \\ System.argv()) do
    spec = prepare!(:write, argv)
    auth = install_connection!(spec)
    print_result!("write acceptance", perform_write_acceptance(auth, spec))
  end

  @spec run_all_acceptance!([String.t()]) :: map()
  def run_all_acceptance!(argv \\ System.argv()) do
    spec = prepare!(:all, argv)
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

  defp prepare!(mode, argv) do
    spec = LiveSpec.parse!(mode, argv)
    spec = Map.put(spec, :token, resolve_token!())

    configure_live_provider!(spec)
    boot_runtime!()
    spec
  end

  defp resolve_token! do
    executable = System.find_executable("gh")

    expect!(
      is_binary(executable),
      "missing GitHub token source; install `gh`, run `gh auth login`, and rerun the live proof"
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
    auth = GitHub.manifest().auth
    binding = InstallBinding.from_personal_access_token(spec.token)

    {:ok, %{install: install, connection: installing_connection}} =
      V2.start_install("github", spec.tenant_id, %{
        actor_id: spec.actor_id,
        auth_type: auth.auth_type,
        profile_id: auth.default_profile,
        subject: spec.subject,
        requested_scopes: auth.requested_scopes,
        metadata: %{proof: "connectors/github live acceptance"},
        now: now
      })

    expect!(install.state == :installing, "install did not start in the installing state")

    expect!(
      installing_connection.state == :installing,
      "connection did not start in the installing state"
    )

    {:ok, %{install: completed_install, connection: connection, credential_ref: credential_ref}} =
      V2.complete_install(
        install.install_id,
        InstallBinding.complete_install_attrs(spec.subject, auth.requested_scopes, binding,
          now: now
        )
      )

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
        required_scopes: auth.requested_scopes,
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
        connection_id: auth.connection.connection_id,
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
      Keyword.get(opts, :issue_number) || first_issue_number!(list_result.output.issues, repo)

    fetch_result = fetch_issue!(auth, repo, issue_number)
    commits_result = list_commits!(auth, repo)
    head_sha = first_commit_sha!(commits_result.output.commits, repo)
    combined_status_result = fetch_combined_status!(auth, repo, head_sha)
    statuses_result = list_commit_statuses!(auth, repo, head_sha)
    check_runs_result = list_check_runs!(auth, repo, head_sha)
    pr_read_result = maybe_perform_pr_read_acceptance(auth, spec, repo)

    expect!(list_result.output.repo == repo, "live issue list returned the wrong repo")
    expect!(fetch_result.output.repo == repo, "live issue fetch returned the wrong repo")
    expect!(commits_result.output.repo == repo, "live commit list returned the wrong repo")
    expect!(combined_status_result.output.ref == head_sha, "combined status used the wrong ref")
    expect!(statuses_result.output.ref == head_sha, "status list used the wrong ref")
    expect!(check_runs_result.output.ref == head_sha, "check-run list used the wrong ref")

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
      evidence_head_sha: head_sha,
      commit_count: commits_result.output.total_count,
      combined_status_state: combined_status_result.output.state,
      status_count: statuses_result.output.total_count,
      check_run_count: check_runs_result.output.total_count,
      pr_read: pr_read_result.summary,
      auth_connection_id: auth.connection.connection_id,
      run_ids:
        [
          list_result.run.run_id,
          fetch_result.run.run_id,
          commits_result.run.run_id,
          combined_status_result.run.run_id,
          statuses_result.run.run_id,
          check_runs_result.run.run_id
        ] ++ pr_read_result.run_ids
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

      pr_result = perform_disposable_pr_acceptance(auth, spec, repo, seed)

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
        disposable_pr: pr_result.summary,
        auth_connection_id: auth.connection.connection_id,
        run_ids:
          [
            create_result.run.run_id,
            fetch_result.run.run_id,
            update_result.run.run_id,
            label_result.run.run_id,
            create_comment_result.run.run_id,
            update_comment_result.run.run_id,
            close_result.run.run_id
          ] ++ pr_result.run_ids
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

  defp fetch_repo!(auth, repo) do
    invoke!(auth, "github.repo.fetch", %{repo: repo})
  end

  defp list_commits!(auth, repo, sha \\ nil) do
    input =
      if is_binary(sha) do
        %{repo: repo, sha: sha, per_page: 1, page: 1}
      else
        %{repo: repo, per_page: 1, page: 1}
      end

    invoke!(auth, "github.commits.list", input)
  end

  defp fetch_combined_status!(auth, repo, ref) do
    invoke!(auth, "github.commit.statuses.get_combined", %{
      repo: repo,
      ref: ref,
      per_page: 10,
      page: 1
    })
  end

  defp list_commit_statuses!(auth, repo, ref) do
    invoke!(auth, "github.commit.statuses.list", %{
      repo: repo,
      ref: ref,
      per_page: 10,
      page: 1
    })
  end

  defp list_check_runs!(auth, repo, ref) do
    invoke!(auth, "github.check_runs.list_for_ref", %{
      repo: repo,
      ref: ref,
      per_page: 10,
      page: 1
    })
  end

  defp maybe_perform_pr_read_acceptance(auth, _spec, repo) do
    list_result = list_prs!(auth, repo)

    case list_result.output.pull_requests do
      [%{pull_number: pull_number} | _rest] when is_integer(pull_number) and pull_number > 0 ->
        perform_discovered_pr_read_acceptance(auth, repo, pull_number, list_result)

      _none ->
        %{
          summary: %{exercised?: false, reason: :no_pull_requests, listed_count: 0},
          run_ids: [list_result.run.run_id]
        }
    end
  end

  defp perform_discovered_pr_read_acceptance(auth, repo, pull_number, list_result) do
    fetch_result = fetch_pr!(auth, repo, pull_number)
    reviews_result = list_pr_reviews!(auth, repo, pull_number)
    comments_result = list_pr_review_comments!(auth, repo, pull_number)

    expect!(list_result.output.repo == repo, "live PR list returned the wrong repo")
    expect!(fetch_result.output.repo == repo, "live PR fetch returned the wrong repo")
    expect!(fetch_result.output.pull_number == pull_number, "live PR fetch returned the wrong PR")
    expect!(reviews_result.output.pull_number == pull_number, "review list used the wrong PR")

    expect!(
      comments_result.output.pull_number == pull_number,
      "review-comment list used the wrong PR"
    )

    %{
      summary: %{
        exercised?: true,
        pull_number: pull_number,
        state: fetch_result.output.state,
        listed_count: list_result.output.total_count,
        review_count: reviews_result.output.total_count,
        review_comment_count: comments_result.output.total_count
      },
      run_ids: [
        list_result.run.run_id,
        fetch_result.run.run_id,
        reviews_result.run.run_id,
        comments_result.run.run_id
      ]
    }
  end

  defp list_prs!(auth, repo) do
    invoke!(auth, "github.pr.list", %{
      repo: repo,
      state: "all",
      per_page: 1,
      page: 1
    })
  end

  defp fetch_pr!(auth, repo, pull_number) do
    invoke!(auth, "github.pr.fetch", %{
      repo: repo,
      pull_number: pull_number
    })
  end

  defp list_pr_reviews!(auth, repo, pull_number) do
    invoke!(auth, "github.pr.reviews.list", %{
      repo: repo,
      pull_number: pull_number,
      per_page: 10,
      page: 1
    })
  end

  defp list_pr_review_comments!(auth, repo, pull_number) do
    invoke!(auth, "github.pr.review_comments.list", %{
      repo: repo,
      pull_number: pull_number,
      per_page: 10,
      page: 1
    })
  end

  defp perform_disposable_pr_acceptance(auth, _spec, repo, seed) do
    repo_result = fetch_repo!(auth, repo)
    default_branch = repo_result.output.default_branch

    expect!(
      is_binary(default_branch) and default_branch != "",
      "repository fetch did not return a default branch"
    )

    base_commits_result = list_commits!(auth, repo, default_branch)
    base_sha = first_commit_sha!(base_commits_result.output.commits, repo)
    branch = unique_branch_name()
    create_ref = "refs/heads/#{branch}"
    delete_ref = "heads/#{branch}"
    scratch_path = "generated/live-e2e/#{branch}.txt"

    create_ref_result = create_ref!(auth, repo, create_ref, base_sha)

    try do
      upsert_result =
        upsert_contents!(
          auth,
          repo,
          scratch_path,
          "Add #{branch} GitHub live proof artifact",
          disposable_pr_content(seed, repo, default_branch, base_sha),
          branch
        )

      create_pr_result =
        create_pr!(
          auth,
          repo,
          "Jido live PR acceptance #{branch}",
          "Disposable PR created by the package-local GitHub live proof.",
          branch,
          default_branch
        )

      created_pr =
        exercise_created_disposable_pr!(
          auth,
          repo,
          create_pr_result,
          upsert_result.output.commit_sha,
          seed
        )

      delete_ref_result = delete_ref!(auth, repo, delete_ref)

      expect!(create_ref_result.output.sha == base_sha, "branch ref used the wrong base sha")

      expect!(
        upsert_result.output.path == scratch_path,
        "scratch file upsert used the wrong path"
      )

      expect!(create_pr_result.output.repo == repo, "PR create returned the wrong repo")

      expect!(
        created_pr.fetch_result.output.pull_number == create_pr_result.output.pull_number,
        "PR fetch returned the wrong PR"
      )

      expect!(
        created_pr.close_result.output.state == "closed",
        "PR close did not return closed state"
      )

      expect!(
        delete_ref_result.output.deleted? == true,
        "branch ref delete did not report success"
      )

      %{
        summary: %{
          repo: repo,
          default_branch: default_branch,
          base_sha: base_sha,
          branch: branch,
          branch_ref: create_ref,
          deleted_ref: delete_ref_result.output.ref,
          scratch_path: scratch_path,
          scratch_commit_sha: upsert_result.output.commit_sha,
          pull_number: create_pr_result.output.pull_number,
          review_id: created_pr.review_result.output.review.review_id,
          review_state: created_pr.review_result.output.review.state,
          review_count: created_pr.reviews_result.output.total_count,
          review_comment_count: created_pr.comments_result.output.total_count,
          close_state: created_pr.close_result.output.state
        },
        run_ids: [
          repo_result.run.run_id,
          base_commits_result.run.run_id,
          create_ref_result.run.run_id,
          upsert_result.run.run_id,
          create_pr_result.run.run_id,
          created_pr.fetch_result.run.run_id,
          created_pr.review_result.run.run_id,
          created_pr.reviews_result.run.run_id,
          created_pr.comments_result.run.run_id,
          created_pr.close_result.run.run_id,
          delete_ref_result.run.run_id
        ]
      }
    rescue
      error ->
        safe_delete_ref(auth, repo, delete_ref)
        reraise(error, __STACKTRACE__)
    end
  end

  defp exercise_created_disposable_pr!(
         auth,
         repo,
         create_pr_result,
         scratch_commit_sha,
         seed
       ) do
    pull_number = create_pr_result.output.pull_number

    try do
      fetch_result = fetch_pr!(auth, repo, pull_number)

      review_result =
        create_pr_review!(
          auth,
          repo,
          pull_number,
          scratch_commit_sha,
          seed.comment_body <> " PR review evidence."
        )

      reviews_result = list_pr_reviews!(auth, repo, pull_number)
      comments_result = list_pr_review_comments!(auth, repo, pull_number)
      close_result = close_pr!(auth, repo, pull_number)

      %{
        fetch_result: fetch_result,
        review_result: review_result,
        reviews_result: reviews_result,
        comments_result: comments_result,
        close_result: close_result
      }
    rescue
      error ->
        safe_close_pr(auth, repo, pull_number)
        reraise(error, __STACKTRACE__)
    end
  end

  defp create_ref!(auth, repo, ref, sha) do
    invoke!(auth, "github.git.ref.create", %{
      repo: repo,
      ref: ref,
      sha: sha
    })
  end

  defp delete_ref!(auth, repo, ref) do
    invoke!(auth, "github.git.ref.delete", %{
      repo: repo,
      ref: ref
    })
  end

  defp upsert_contents!(auth, repo, path, message, content, branch) do
    invoke!(auth, "github.contents.upsert", %{
      repo: repo,
      path: path,
      message: message,
      content: content,
      branch: branch
    })
  end

  defp create_pr!(auth, repo, title, body, head, base) do
    invoke!(auth, "github.pr.create", %{
      repo: repo,
      title: title,
      body: body,
      head: head,
      base: base,
      draft: false,
      maintainer_can_modify: true
    })
  end

  defp create_pr_review!(auth, repo, pull_number, commit_id, body) do
    invoke!(auth, "github.pr.review.create", %{
      repo: repo,
      pull_number: pull_number,
      body: body,
      event: "COMMENT",
      commit_id: commit_id
    })
  end

  defp close_pr!(auth, repo, pull_number) do
    invoke!(auth, "github.pr.update", %{
      repo: repo,
      pull_number: pull_number,
      state: "closed"
    })
  end

  defp write_seed do
    marker = unique_marker()

    %{
      title: "Jido live acceptance #{marker}",
      body: "Created by the package-local GitHub live proof script.",
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

  defp safe_close_pr(auth, repo, pull_number)
       when is_binary(repo) and is_integer(pull_number) do
    _ =
      try do
        close_pr!(auth, repo, pull_number)
      rescue
        _error -> :noop
      end

    :ok
  end

  defp safe_close_pr(_auth, _repo, _pull_number), do: :ok

  defp safe_delete_ref(auth, repo, ref)
       when is_binary(repo) and is_binary(ref) do
    _ =
      try do
        delete_ref!(auth, repo, ref)
      rescue
        _error -> :noop
      end

    :ok
  end

  defp safe_delete_ref(_auth, _repo, _ref), do: :ok

  defp disposable_pr_content(seed, repo, default_branch, base_sha) do
    """
    #{seed.title}

    Repository: #{repo}
    Default branch: #{default_branch}
    Base commit: #{base_sha}

    This file is created on a disposable branch, carried into a disposable pull
    request, and deleted by the package-local GitHub live proof.
    """
  end

  defp unique_branch_name do
    "jido-live-e2e-#{unique_marker()}"
  end

  defp unique_marker do
    "#{System.system_time(:second)}-#{System.unique_integer([:positive])}"
  end

  defp first_issue_number!([], repo) do
    raise ArgumentError,
          """
          the read-only proof needs #{repo} to have at least one existing issue.

          For the combined smoke run, `scripts/live_acceptance.sh all` can bootstrap a writable repo issue automatically.
          """
  end

  defp first_issue_number!([issue | _rest], _repo), do: issue.issue_number

  defp first_commit_sha!([], repo) do
    raise ArgumentError, "the read proof needs #{repo} to have at least one commit"
  end

  defp first_commit_sha!([commit | _rest], _repo), do: commit.sha

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
