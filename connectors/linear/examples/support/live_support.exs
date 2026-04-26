defmodule Jido.Integration.V2.Connectors.Linear.LiveSupport do
  @moduledoc false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.Connectors.Linear
  alias Jido.Integration.V2.Connectors.Linear.ClientFactory
  alias Jido.Integration.V2.Connectors.Linear.InstallBinding
  alias Jido.Integration.V2.Connectors.Linear.LiveSpec

  @runtime_apps [
    :jido_integration_v2_auth,
    :jido_integration_v2_control_plane
  ]

  @comment_delete_mutation """
  mutation JidoLinearCommentDelete($id: String!) {
    commentDelete(id: $id) {
      success
    }
  }
  """

  @spec run_auth_lifecycle!([String.t()]) :: map()
  def run_auth_lifecycle!(argv \\ System.argv()) do
    {spec, api_key} = prepare!(:auth, argv)
    auth = install_connection!(spec, api_key)
    print_result!("auth lifecycle", auth_summary(auth))
  end

  @spec run_read_acceptance!([String.t()]) :: map()
  def run_read_acceptance!(argv \\ System.argv()) do
    {spec, api_key} = prepare!(:read, argv)
    auth = install_connection!(spec, api_key)
    print_result!("read acceptance", perform_read_acceptance(auth, spec))
  end

  @spec run_write_acceptance!([String.t()]) :: map()
  def run_write_acceptance!(argv \\ System.argv()) do
    {spec, api_key} = prepare!(:write, argv)
    auth = install_connection!(spec, api_key)
    print_result!("write acceptance", perform_write_acceptance(auth, spec))
  end

  @spec run_all_acceptance!([String.t()]) :: map()
  def run_all_acceptance!(argv \\ System.argv()) do
    {spec, api_key} = prepare!(:all, argv)
    auth = install_connection!(spec, api_key)
    list_result = list_issues!(auth, spec)
    issue = first_issue!(list_result.output.issues)

    result = %{
      auth: auth_summary(auth),
      read: perform_read_acceptance(auth, spec, list_result: list_result, issue: issue),
      write: perform_write_acceptance(auth, spec, list_result: list_result, issue: issue)
    }

    print_result!("full acceptance", result)
  end

  defp prepare!(mode, argv) do
    spec = LiveSpec.parse!(mode, argv)
    api_key = resolve_api_key!(spec.api_key_source)

    configure_live_provider!(spec)
    boot_runtime!()

    {spec, api_key}
  end

  defp resolve_api_key!(:stdin) do
    :stdio
    |> IO.read(:eof)
    |> normalize_api_key!("standard input")
  end

  defp resolve_api_key!({:file, path}) do
    path
    |> File.read!()
    |> normalize_api_key!(path)
  end

  defp normalize_api_key!(value, source) when is_binary(value) do
    value
    |> String.trim()
    |> tap(fn trimmed ->
      expect!(trimmed != "", "Linear API key source #{source} was empty")
    end)
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
    :ok = V2.register_connector(Linear)
  end

  defp configure_live_provider!(spec) do
    Application.put_env(:jido_integration_v2_linear, ClientFactory, live_client_opts(spec))
  end

  defp live_client_opts(spec) do
    []
    |> maybe_put(:base_url, spec.api_base_url)
    |> maybe_put_timeout(spec.timeout_ms)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_timeout(opts, nil), do: opts

  defp maybe_put_timeout(opts, timeout_ms) do
    Keyword.update(opts, :req_options, [receive_timeout: timeout_ms], fn req_options ->
      Keyword.put(req_options, :receive_timeout, timeout_ms)
    end)
  end

  defp install_connection!(spec, api_key) do
    now = DateTime.utc_now()
    auth = Linear.manifest().auth
    binding = InstallBinding.from_api_key(api_key)

    {:ok, %{install: install, connection: installing_connection}} =
      V2.start_install("linear", spec.tenant_id, %{
        actor_id: spec.actor_id,
        auth_type: auth.auth_type,
        profile_id: auth.default_profile,
        subject: spec.subject,
        requested_scopes: auth.requested_scopes,
        metadata: %{proof: "connectors/linear live acceptance"},
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
      lease.payload == %{api_key: api_key},
      "lease payload was not minimized to the API key"
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

    refute_secret_leaks!(result, auth.lease.payload.api_key)
    refute_secret_leaks!(V2.events(result.run.run_id), auth.lease.payload.api_key)
    refute_secret_leaks!(V2.run_artifacts(result.run.run_id), auth.lease.payload.api_key)
    result
  end

  defp perform_read_acceptance(auth, spec, opts \\ []) do
    viewer_result = invoke!(auth, "linear.users.get_self", %{})
    list_result = Keyword.get(opts, :list_result) || list_issues!(auth, spec)
    issue = Keyword.get(opts, :issue) || first_issue!(list_result.output.issues)
    fetch_result = fetch_issue!(auth, issue.id)
    fetched_issue = fetch_result.output.issue
    workflow_states_result = list_workflow_states_for_issue!(auth, spec, fetched_issue)

    expect!(fetch_result.output.issue.id == issue.id, "live issue fetch returned the wrong issue")

    expect!(
      fetch_result.output.issue.identifier == issue.identifier,
      "live issue fetch returned the wrong identifier"
    )

    expect!(
      list_result.output.auth_binding == fetch_result.output.auth_binding,
      "live read changed auth binding between calls"
    )

    %{
      viewer_user_id: viewer_result.output.user.id,
      listed_issue_count: length(list_result.output.issues),
      fetched_issue_id: fetched_issue.id,
      fetched_issue_identifier: fetched_issue.identifier,
      workflow_state_count: length(workflow_states_result.output.workflow_states),
      auth_connection_id: auth.connection.connection_id,
      run_ids: [
        viewer_result.run.run_id,
        list_result.run.run_id,
        fetch_result.run.run_id,
        workflow_states_result.run.run_id
      ]
    }
  end

  defp perform_write_acceptance(auth, spec, opts \\ []) do
    list_result = Keyword.get(opts, :list_result) || list_issues!(auth, spec)
    issue = Keyword.get(opts, :issue) || first_issue!(list_result.output.issues)
    fetch_result = fetch_issue!(auth, issue.id)
    fetched_issue = fetch_result.output.issue
    state_id = current_state_id!(fetched_issue)
    seed = write_seed(fetched_issue)

    create_comment_result =
      invoke!(auth, "linear.comments.create", %{
        issue_id: fetched_issue.id,
        body: seed.comment_body
      })

    comment_id = created_comment_id!(create_comment_result)

    try do
      update_comment_result =
        invoke!(auth, "linear.comments.update", %{
          comment_id: comment_id,
          body: seed.updated_comment_body
        })

      update_issue_result =
        invoke!(auth, "linear.issues.update", %{
          issue_id: fetched_issue.id,
          state_id: state_id
        })

      delete_comment_result =
        unless spec.keep_terminal_comment? do
          delete_comment!(auth, comment_id)
        end

      expect!(create_comment_result.output.success, "comment create did not report success")
      expect!(update_comment_result.output.success, "comment update did not report success")
      expect!(update_issue_result.output.success, "issue update did not report success")

      expect!(
        update_comment_result.output.comment.body == seed.updated_comment_body,
        "comment update did not persist the body"
      )

      expect!(
        update_issue_result.output.issue.state.id == state_id,
        "issue update did not keep the dynamically discovered state"
      )

      %{
        issue_id: fetched_issue.id,
        issue_identifier: fetched_issue.identifier,
        comment_id: comment_id,
        terminal_publication: %{
          comment_id: comment_id,
          body: update_comment_result.output.comment.body,
          preserved_as_terminal_evidence?: spec.keep_terminal_comment?
        },
        cleanup: %{comment_deleted?: not spec.keep_terminal_comment?},
        auth_connection_id: auth.connection.connection_id,
        run_ids:
          [
            list_result.run.run_id,
            fetch_result.run.run_id,
            create_comment_result.run.run_id,
            update_comment_result.run.run_id,
            update_issue_result.run.run_id
          ] ++ maybe_result_run_ids(delete_comment_result)
      }
    rescue
      error ->
        safe_delete_comment(auth, comment_id)
        reraise(error, __STACKTRACE__)
    end
  end

  defp list_issues!(auth, spec) do
    invoke!(auth, "linear.issues.list", %{first: spec.read_limit})
  end

  defp fetch_issue!(auth, issue_id) do
    invoke!(auth, "linear.issues.retrieve", %{issue_id: issue_id})
  end

  defp list_workflow_states_for_issue!(auth, spec, %{team: %{id: team_id}})
       when is_binary(team_id) and team_id != "" do
    invoke!(auth, "linear.workflow_states.list", %{
      first: spec.read_limit,
      filter: %{team_id: team_id}
    })
  end

  defp list_workflow_states_for_issue!(auth, spec, _issue) do
    invoke!(auth, "linear.workflow_states.list", %{first: spec.read_limit})
  end

  defp delete_comment!(auth, comment_id) when is_binary(comment_id) do
    result =
      invoke!(auth, "linear.graphql.execute", %{
        query: @comment_delete_mutation,
        variables: %{id: comment_id},
        operation_name: "JidoLinearCommentDelete"
      })

    expect!(
      get_in(result.output.data, ["commentDelete", "success"]) == true,
      "comment cleanup did not report success"
    )

    result
  end

  defp safe_delete_comment(_auth, nil), do: :ok

  defp safe_delete_comment(auth, comment_id) when is_binary(comment_id) do
    _ =
      try do
        delete_comment!(auth, comment_id)
      rescue
        _error -> :noop
      end

    :ok
  end

  defp maybe_result_run_ids(nil), do: []
  defp maybe_result_run_ids(result), do: [result.run.run_id]

  defp first_issue!([]) do
    raise ArgumentError,
          """
          the Linear live proof needs at least one issue visible to the supplied credential.

          The proof intentionally discovers provider ids from Linear list responses; it does not accept static issue ids as operator input.
          """
  end

  defp first_issue!([issue | _rest]), do: issue

  defp current_state_id!(%{state: %{id: state_id}}) when is_binary(state_id) and state_id != "" do
    state_id
  end

  defp current_state_id!(issue) do
    raise ArgumentError,
          "the discovered Linear issue #{inspect(issue.identifier)} did not include a current state id"
  end

  defp created_comment_id!(%{output: %{comment: %{id: comment_id}}})
       when is_binary(comment_id) and comment_id != "" do
    comment_id
  end

  defp created_comment_id!(_result) do
    raise ArgumentError, "Linear comment create did not return a comment id"
  end

  defp write_seed(issue) do
    marker = Integer.to_string(System.system_time(:second))
    identifier = issue.identifier || issue.id

    %{
      comment_body: "Jido Linear live proof #{marker} on #{identifier}.",
      updated_comment_body: "Jido Linear live proof #{marker} on #{identifier}. Updated."
    }
  end

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

  defp refute_secret_leaks!(term, api_key) do
    expect!(
      not String.contains?(inspect(term), api_key),
      "live proof surfaced the raw Linear API key in runtime output"
    )
  end

  defp print_result!(label, result) do
    IO.puts("Linear #{label} proof passed.")
    IO.inspect(result, label: "result")
    result
  end

  defp expect!(true, _message), do: :ok
  defp expect!(false, message), do: raise(ArgumentError, message)
end
