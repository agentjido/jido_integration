defmodule Jido.Integration.V2.Connectors.Notion.LiveSupport do
  @moduledoc false

  alias Jido.Integration.V2, as: V2
  alias Jido.Integration.V2.Connectors.Notion
  alias Jido.Integration.V2.Connectors.Notion.InstallBinding
  alias Jido.Integration.V2.Connectors.Notion.LiveEnv
  alias Jido.Integration.V2.Connectors.Notion.PermissionProfile

  @runtime_apps [
    :jido_integration_v2_auth,
    :jido_integration_v2_control_plane,
    :jido_integration_v2_direct_runtime,
    :jido_integration_v2_session_kernel,
    :jido_integration_v2_stream_runtime
  ]

  @spec run_auth_lifecycle!() :: map()
  def run_auth_lifecycle! do
    spec = prepare!(:auth)
    request = authorization_request!(spec)
    code = resolve_authorization_code!(spec, request)
    token = exchange_code!(spec, code)

    auth =
      install_connection!(spec, :content_publishing, InstallBinding.from_token(token), "auth")

    print_result!("auth lifecycle", %{
      authorization_url: request.url,
      state: Map.get(request, :state),
      auth: auth_summary(auth)
    })
  end

  @spec run_read_acceptance!() :: map()
  def run_read_acceptance! do
    spec = prepare!(:read)

    auth =
      install_connection!(spec, :workspace_read, InstallBinding.from_live_spec(spec), "read")

    self_result = invoke!(auth, "notion.users.get_self", %{}, spec)
    page_result = invoke!(auth, "notion.pages.retrieve", %{page_id: spec.read_page_id}, spec)

    print_result!("read acceptance", %{
      auth: auth_summary(auth),
      get_self: review_summary(self_result),
      retrieve_page: review_summary(page_result),
      page_id: get_in(page_result.output, [:data, "id"]),
      page_url: get_in(page_result.output, [:data, "url"])
    })
  end

  @spec run_write_acceptance!() :: map()
  def run_write_acceptance! do
    spec = prepare!(:write)

    auth =
      install_connection!(
        spec,
        :content_publishing,
        InstallBinding.from_live_spec(spec),
        "write"
      )

    create_result = invoke!(auth, "notion.pages.create", create_page_input(spec), spec)
    page_id = created_page_id!(create_result)

    try do
      append_result =
        invoke!(auth, "notion.blocks.append_children", append_children_input(page_id), spec)

      update_result = invoke!(auth, "notion.pages.update", update_page_input(spec, page_id), spec)

      comment_result =
        invoke!(auth, "notion.comments.create", create_comment_input(page_id), spec)

      cleanup = archive_page!(auth, page_id, spec)

      print_result!("write acceptance", %{
        auth: auth_summary(auth),
        create_page: review_summary(create_result),
        append_children: review_summary(append_result),
        update_page: review_summary(update_result),
        create_comment: review_summary(comment_result),
        cleanup: review_summary(cleanup),
        page_id: page_id,
        page_url: get_in(create_result.output, [:data, "url"])
      })
    rescue
      error ->
        safe_archive_page(auth, page_id, spec)
        reraise(error, __STACKTRACE__)
    end
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

              See connectors/notion/docs/live_acceptance.md for the package-local runbook.
              """
    end

    boot_runtime!()
    LiveEnv.spec(env)
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
    :ok = V2.register_connector(Notion)
  end

  defp authorization_request!(spec) do
    case NotionSDK.OAuth.authorization_request(
           client_id: spec.client_id,
           redirect_uri: spec.redirect_uri,
           generate_state: true
         ) do
      {:ok, request} ->
        request

      {:error, error} ->
        raise_oauth_error!("failed to build Notion authorization request", error)
    end
  end

  defp resolve_authorization_code!(spec, request) do
    cond do
      present?(spec.auth_code) ->
        spec.auth_code

      present?(spec.callback_url) ->
        callback_code!(spec.callback_url)

      true ->
        IO.puts("Open this URL in a browser and approve the Notion integration:")
        IO.puts(request.url)

        input =
          IO.gets("\nPaste the final callback URL or the temporary authorization code: ")
          |> to_string()
          |> String.trim()

        expect!(input != "", "missing Notion callback URL or authorization code")

        if String.contains?(input, "://") do
          callback_code!(input)
        else
          input
        end
    end
  end

  defp callback_code!(callback_url) do
    uri = URI.parse(callback_url)
    query = URI.decode_query(uri.query || "")

    cond do
      present?(query["code"]) ->
        query["code"]

      present?(query["error"]) ->
        description = query["error_description"] || query["error"]
        raise "Notion OAuth callback returned an error: #{description}"

      true ->
        raise ArgumentError, "callback URL did not include a Notion authorization code"
    end
  end

  defp exchange_code!(spec, code) do
    opts =
      []
      |> Keyword.put(:client_id, spec.client_id)
      |> Keyword.put(:client_secret, spec.client_secret)
      |> Keyword.put(:redirect_uri, spec.redirect_uri)
      |> maybe_put(:base_url, spec.api_base_url)
      |> maybe_put(:timeout_ms, spec.timeout_ms)

    case NotionSDK.OAuth.exchange_code(code, opts) do
      {:ok, token} ->
        token

      {:error, error} ->
        raise_oauth_error!("failed to exchange the Notion authorization code", error)
    end
  end

  defp install_connection!(spec, permission_profile, binding, proof_mode) do
    now = DateTime.utc_now()
    scopes = PermissionProfile.scopes(permission_profile)

    {:ok, %{install: install, connection: installing_connection}} =
      V2.start_install("notion", spec.tenant_id, %{
        actor_id: spec.actor_id,
        auth_type: :oauth2,
        subject: spec.subject,
        requested_scopes: scopes,
        metadata: %{
          proof: "connectors/notion #{proof_mode} live acceptance",
          permission_profile: Atom.to_string(permission_profile),
          redirect_uri: spec.redirect_uri
        },
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
        InstallBinding.complete_install_attrs(spec.subject, scopes, binding, now: now)
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
        required_scopes: scopes,
        ttl_seconds: 300,
        now: now
      })

    expect!(lease.subject == spec.subject, "lease subject did not match the install subject")

    expect!(
      present?(secret_value(lease.payload, "access_token")),
      "lease did not include an access token"
    )

    refute_secret!(
      lease.payload,
      "refresh_token",
      "lease should not expose the durable refresh token"
    )

    %{
      install: completed_install,
      connection: connection,
      credential_ref: credential_ref,
      lease: lease
    }
  end

  defp invoke!(auth, capability_id, input, spec) do
    {:ok, capability} = V2.fetch_capability(capability_id)

    {:ok, result} =
      V2.invoke(capability_id, input,
        credential_ref: auth.credential_ref,
        actor_id: auth.connection.actor_id,
        tenant_id: auth.connection.tenant_id,
        environment: :prod,
        allowed_operations: [capability_id],
        sandbox: capability.metadata.policy.sandbox,
        notion_client: live_client_opts(spec)
      )

    assert_token_safe!(result, spec)
    result
  end

  defp create_page_input(spec) do
    %{
      parent: %{"data_source_id" => spec.write_parent_data_source_id},
      properties: %{
        spec.write_title_property => %{
          "title" => [%{"text" => %{"content" => unique_title(spec.write_page_title)}}]
        }
      },
      children: [
        %{
          "object" => "block",
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{"type" => "text", "text" => %{"content" => "Created by Jido live acceptance"}}
            ]
          }
        }
      ]
    }
  end

  defp update_page_input(spec, page_id) do
    %{
      page_id: page_id,
      archived: false,
      properties: %{
        spec.write_title_property => %{
          "title" => [
            %{"text" => %{"content" => unique_title(spec.write_page_title <> " updated")}}
          ]
        }
      }
    }
  end

  defp append_children_input(page_id) do
    %{
      block_id: page_id,
      children: [
        %{
          "object" => "block",
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [
              %{"type" => "text", "text" => %{"content" => "Additional live acceptance content"}}
            ]
          }
        }
      ]
    }
  end

  defp create_comment_input(page_id) do
    %{
      parent: %{"page_id" => page_id},
      rich_text: [
        %{"type" => "text", "text" => %{"content" => "Comment created by Jido live acceptance"}}
      ]
    }
  end

  defp archive_page!(auth, page_id, spec) do
    invoke!(auth, "notion.pages.update", %{page_id: page_id, archived: true}, spec)
  end

  defp safe_archive_page(auth, page_id, spec) do
    archive_page!(auth, page_id, spec)
  rescue
    _error -> :ok
  end

  defp review_summary(result) do
    %{
      run_id: result.run.run_id,
      attempt_id: result.attempt.attempt_id,
      capability_id: result.run.capability_id,
      event_types: event_types(result.run.run_id),
      artifact_keys: artifact_keys(result.run.run_id)
    }
  end

  defp auth_summary(auth) do
    %{
      install_id: auth.install.install_id,
      connection_id: auth.connection.connection_id,
      credential_ref_id: auth.credential_ref.id,
      granted_scopes: auth.connection.granted_scopes,
      lease_payload_keys:
        auth.lease.payload |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
      workspace_id: secret_value(auth.lease.payload, "workspace_id"),
      workspace_name: secret_value(auth.lease.payload, "workspace_name"),
      bot_id: secret_value(auth.lease.payload, "bot_id")
    }
  end

  defp event_types(run_id) do
    run_id
    |> V2.events()
    |> Enum.map(& &1.type)
  end

  defp artifact_keys(run_id) do
    run_id
    |> V2.run_artifacts()
    |> Enum.map(& &1.key)
    |> Enum.sort()
  end

  defp live_client_opts(spec) do
    []
    |> maybe_put(:base_url, spec.api_base_url)
    |> maybe_put(:timeout_ms, spec.timeout_ms)
  end

  defp assert_token_safe!(result, spec) do
    secrets =
      [spec.access_token, spec.refresh_token]
      |> Enum.filter(&present?/1)

    Enum.each(secrets, fn secret ->
      expect!(
        not contains_secret?(result.output, secret),
        "runtime output leaked a raw Notion secret"
      )

      expect!(
        not Enum.any?(V2.events(result.run.run_id), &contains_secret?(&1, secret)),
        "runtime events leaked a raw Notion secret"
      )

      expect!(
        not Enum.any?(V2.run_artifacts(result.run.run_id), &contains_secret?(&1, secret)),
        "artifact refs leaked a raw Notion secret"
      )
    end)
  end

  defp contains_secret?(value, secret) do
    inspect(value, limit: :infinity, printable_limit: :infinity)
    |> String.contains?(secret)
  end

  defp created_page_id!(result) do
    page_id = get_in(result.output, [:data, "id"])
    expect!(present?(page_id), "write proof did not return a created page id")
    page_id
  end

  defp unique_title(prefix) do
    "#{prefix} #{System.system_time(:second)}"
  end

  defp secret_value(secret, key) when is_map(secret) do
    Map.get(secret, key) || Map.get(secret, String.to_atom(key))
  end

  defp secret_value(_secret, _key), do: nil

  defp refute_secret!(secret, key, message) do
    expect!(is_nil(secret_value(secret, key)), message)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp print_result!(label, result) do
    IO.puts(String.upcase(label))
    IO.puts(Jason.encode!(result, pretty: true))
    result
  end

  defp expect!(true, _message), do: :ok
  defp expect!(false, message), do: raise(RuntimeError, message)

  defp raise_oauth_error!(prefix, error) do
    if Kernel.is_exception(error) do
      raise "#{prefix}: #{Exception.message(error)}"
    else
      raise "#{prefix}: #{inspect(error)}"
    end
  end
end
