defmodule Jido.Integration.Execution do
  @moduledoc false

  alias Jido.Integration.Auth.Credential
  alias Jido.Integration.{Error, Gateway, Operation, Schema, Telemetry}
  alias Jido.Integration.Gateway.Policy.Default

  @spec execute(module(), Operation.Envelope.t(), keyword()) ::
          {:ok, Operation.Result.t()} | {:error, Error.t()}
  def execute(adapter, %Operation.Envelope{} = envelope, opts \\ []) do
    with {:ok, manifest} <- fetch_manifest(adapter),
         {:ok, operation} <- fetch_operation(manifest, envelope.operation_id),
         :ok <- validate_input(operation, envelope),
         :ok <- validate_auth_options(opts),
         :ok <- ensure_auth_context(operation, opts),
         :ok <- check_scopes(manifest, operation, envelope, opts),
         :ok <- apply_gateway(manifest, envelope, opts),
         {:ok, opts} <- resolve_token(manifest, envelope, opts),
         {:ok, result} <- run_adapter(adapter, envelope, opts),
         :ok <- validate_output(operation, result) do
      {:ok, Operation.Result.new(result)}
    end
  end

  defp fetch_manifest(adapter) do
    case adapter.manifest() do
      %Jido.Integration.Manifest{} = manifest ->
        {:ok, manifest}

      manifest ->
        {:error,
         Error.new(:internal, "Adapter returned an invalid manifest",
           code: "connector.invalid_manifest",
           upstream_context: %{"manifest" => inspect(manifest)}
         )}
    end
  rescue
    e ->
      {:error,
       Error.new(:internal, "Failed to load adapter manifest: #{Exception.message(e)}",
         code: "connector.invalid_manifest",
         upstream_context: %{"exception" => Exception.message(e)}
       )}
  end

  defp fetch_operation(manifest, operation_id) do
    case find_operation(manifest, operation_id) do
      nil ->
        {:error,
         Error.new(:invalid_request, "Unknown operation: #{operation_id}",
           code: "operation.unknown",
           upstream_context: %{"connector_id" => manifest.id}
         )}

      operation ->
        {:ok, operation}
    end
  end

  defp validate_input(operation, envelope) do
    Schema.validate(operation.input_schema, envelope.args,
      message: "Operation input does not match the declared schema for #{operation.id}",
      code: "operation.invalid_input",
      class: :invalid_request
    )
  end

  defp validate_output(operation, result) do
    Schema.validate(operation.output_schema, result,
      message:
        "Connector returned a payload that does not match the declared output schema for #{operation.id}",
      code: "connector.invalid_result",
      class: :internal
    )
  end

  defp validate_auth_options(opts) do
    if Keyword.has_key?(opts, :auth_server) && Keyword.has_key?(opts, :auth_bridge) do
      {:error,
       Error.new(:invalid_request, "auth_server and auth_bridge are mutually exclusive",
         code: "auth.conflicting_context"
       )}
    else
      :ok
    end
  end

  defp ensure_auth_context(operation, opts) do
    if operation.required_scopes == [] do
      :ok
    else
      auth_bridge = Keyword.get(opts, :auth_bridge)
      auth_server = Keyword.get(opts, :auth_server)
      connection_id = Keyword.get(opts, :connection_id)

      cond do
        auth_server && connection_id ->
          :ok

        auth_bridge && connection_id ->
          :ok

        true ->
          {:error,
           Error.new(:auth_failed, "Operation requires an authenticated connection",
             code: "auth.context_required"
           )}
      end
    end
  end

  defp check_scopes(manifest, operation, envelope, opts) do
    if operation.required_scopes == [] do
      :ok
    else
      auth_server = Keyword.get(opts, :auth_server)

      if auth_server do
        check_scopes_via_server(
          auth_server,
          opts,
          operation.required_scopes,
          manifest.id,
          envelope.context
        )
      else
        check_scopes_via_bridge(opts, operation.required_scopes)
      end
    end
  end

  defp check_scopes_via_server(auth_server, opts, required_scopes, connector_id, context) do
    connection_id = Keyword.fetch!(opts, :connection_id)

    case apply(auth_server_module(), :check_connection_scopes, [
           auth_server,
           connection_id,
           required_scopes,
           [connector_id: connector_id, context: auth_context(context, opts)]
         ]) do
      :ok ->
        :ok

      {:error, :connector_mismatch} ->
        {:error,
         Error.new(:auth_failed, "Connection is bound to a different connector",
           code: "auth.connector_mismatch"
         )}

      {:error, {:blocked_state, state}} ->
        {:error,
         Error.new(:auth_failed, "Connection state blocks execution: #{state}",
           code: "auth.connection_blocked",
           upstream_context: %{"state" => to_string(state)}
         )}

      {:error, %{missing_scopes: _} = reason} ->
        {:error, normalize_scope_error(reason)}

      {:error, :not_found} ->
        {:error,
         Error.new(:auth_failed, "Connection not found", code: "auth.connection_not_found")}
    end
  rescue
    e ->
      {:error,
       Error.new(:internal, "Scope validation failed: #{Exception.message(e)}",
         code: "auth.scope_check_failed",
         upstream_context: %{"exception" => Exception.message(e)}
       )}
  end

  defp check_scopes_via_bridge(opts, required_scopes) do
    auth_bridge = Keyword.fetch!(opts, :auth_bridge)
    connection_id = Keyword.fetch!(opts, :connection_id)

    case auth_bridge.check_scopes(connection_id, required_scopes) do
      :ok ->
        :ok

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error, normalize_scope_error(reason)}
    end
  rescue
    e ->
      {:error,
       Error.new(:internal, "Scope validation failed: #{Exception.message(e)}",
         code: "auth.scope_check_failed",
         upstream_context: %{"exception" => Exception.message(e)}
       )}
  end

  defp apply_gateway(manifest, envelope, opts) do
    case gateway_policies(opts) do
      [] ->
        :ok

      policies ->
        metadata = %{
          "connector_id" => manifest.id,
          "operation_id" => envelope.operation_id
        }

        case Gateway.check_chain(
               policies,
               gateway_envelope(manifest, envelope),
               gateway_pressure(opts)
             ) do
          :admit ->
            _ = Telemetry.emit("jido.integration.gateway.admitted", %{}, metadata)
            :ok

          :backoff ->
            _ = Telemetry.emit("jido.integration.gateway.backoff", %{}, metadata)

            {:error,
             Error.new(:rate_limited, "Gateway requested backoff for #{envelope.operation_id}",
               code: "gateway.backoff",
               upstream_context: metadata
             )}

          :shed ->
            _ = Telemetry.emit("jido.integration.gateway.shed", %{}, metadata)

            {:error,
             Error.new(:rate_limited, "Gateway shed #{envelope.operation_id}",
               code: "gateway.shed",
               upstream_context: metadata
             )}
        end
    end
  end

  defp gateway_policies(opts) do
    case Keyword.get(opts, :gateway_policies) do
      nil ->
        case Keyword.get(opts, :gateway_policy) do
          nil -> [Default]
          policy -> [policy]
        end

      policies when is_list(policies) ->
        policies
    end
  end

  defp gateway_pressure(opts) do
    Keyword.get(opts, :gateway_pressure, %{})
  end

  defp gateway_envelope(manifest, envelope) do
    %{
      connector_id: manifest.id,
      operation_id: envelope.operation_id,
      context: envelope.context,
      auth_ref: envelope.auth_ref
    }
  end

  defp resolve_token(manifest, envelope, opts) do
    case token_resolution_target(envelope, opts) do
      {:ok, auth_server, auth_ref} ->
        resolve_token_from_auth_server(manifest, envelope, opts, auth_server, auth_ref)

      {:connection, auth_server, connection_id} ->
        with {:ok, auth_ref} <- auth_ref_for_connection(auth_server, connection_id),
             {:ok, resolved_opts} <-
               resolve_token_from_auth_server(manifest, envelope, opts, auth_server, auth_ref) do
          {:ok, Keyword.put_new(resolved_opts, :auth_ref, auth_ref)}
        else
          :skip -> {:ok, opts}
          {:error, %Error{} = error} -> {:error, error}
        end

      :skip ->
        {:ok, opts}
    end
  end

  defp token_resolution_target(envelope, opts) do
    case {
      Keyword.get(opts, :auth_server),
      Keyword.get(opts, :auth_ref) || envelope.auth_ref,
      Keyword.get(opts, :connection_id)
    } do
      {auth_server, auth_ref, _connection_id}
      when not is_nil(auth_server) and not is_nil(auth_ref) ->
        {:ok, auth_server, auth_ref}

      {auth_server, nil, connection_id}
      when not is_nil(auth_server) and not is_nil(connection_id) ->
        {:connection, auth_server, connection_id}

      _ ->
        :skip
    end
  end

  defp auth_ref_for_connection(auth_server, connection_id) do
    case apply(auth_server_module(), :get_connection, [auth_server, connection_id]) do
      {:ok, %{auth_ref: auth_ref}} when is_binary(auth_ref) ->
        {:ok, auth_ref}

      {:ok, _connection} ->
        :skip

      {:error, :not_found} ->
        {:error, token_resolution_error(:connection_not_found)}

      {:error, reason} ->
        {:error, token_resolution_error(reason)}
    end
  rescue
    e ->
      {:error,
       Error.new(:internal, "Failed to resolve connection credential: #{Exception.message(e)}",
         code: "auth.connection_resolution_failed",
         upstream_context: %{"exception" => Exception.message(e)}
       )}
  end

  defp resolve_token_from_auth_server(manifest, envelope, opts, auth_server, auth_ref) do
    case apply(auth_server_module(), :resolve_credential, [
           auth_server,
           auth_ref,
           auth_context(envelope.context, opts, connector_id: manifest.id)
         ]) do
      {:ok, cred} ->
        {:ok,
         opts
         |> Keyword.put(:auth_ref, auth_ref)
         |> Keyword.put(:credential, cred)
         |> maybe_put_token(Credential.secret_value(cred))}

      {:error, reason} ->
        {:error, token_resolution_error(reason)}
    end
  end

  defp maybe_put_token(opts, nil), do: opts
  defp maybe_put_token(opts, token), do: Keyword.put(opts, :token, token)

  defp token_resolution_error(:credential_not_linked) do
    Error.new(:auth_failed, "Connection has no linked credential",
      code: "auth.credential_not_linked"
    )
  end

  defp token_resolution_error(:connection_not_found) do
    Error.new(:auth_failed, "Connection not found", code: "auth.connection_not_found")
  end

  defp token_resolution_error(:scope_violation) do
    Error.new(:auth_failed, "Credential scope mismatch for connector",
      code: "auth.scope_violation"
    )
  end

  defp token_resolution_error(:not_found) do
    Error.new(:auth_failed, "Credential not found for auth_ref",
      code: "auth.credential_not_found"
    )
  end

  defp token_resolution_error(:refresh_failed) do
    Error.new(:auth_failed, "Token refresh failed, re-authentication required",
      code: "auth.refresh_failed"
    )
  end

  defp token_resolution_error(:refresh_retryable) do
    Error.new(:unavailable, "Token refresh failed transiently", code: "auth.refresh_retryable")
  end

  defp token_resolution_error(reason) do
    Error.new(:auth_failed, "Token resolution failed: #{inspect(reason)}",
      code: "auth.token_resolution_failed"
    )
  end

  defp auth_context(context, opts, extra \\ []) do
    %{
      connector_id: Keyword.get(extra, :connector_id),
      trace_id: Map.get(context, "trace_id"),
      span_id: Map.get(context, "span_id"),
      actor_id: Keyword.get(opts, :actor_id)
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp run_adapter(adapter, envelope, opts) do
    run_opts =
      opts
      |> Keyword.put_new(:auth_ref, envelope.auth_ref)
      |> Keyword.put_new(:timeout_ms, envelope.timeout_ms)

    case adapter.run(envelope.operation_id, envelope.args, run_opts) do
      {:ok, result} when is_map(result) ->
        {:ok, result}

      {:ok, result} ->
        {:error,
         Error.new(:internal, "Connector returned a non-map result",
           code: "connector.invalid_result",
           upstream_context: %{"result" => inspect(result)}
         )}

      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error,
         Error.new(:internal, "Connector returned a non-normalized error",
           code: "connector.invalid_error",
           upstream_context: %{"reason" => inspect(reason)}
         )}

      other ->
        {:error,
         Error.new(:internal, "Connector returned an unexpected response",
           code: "connector.invalid_result",
           upstream_context: %{"response" => inspect(other)}
         )}
    end
  rescue
    e ->
      {:error,
       Error.new(:internal, "Connector execution failed: #{Exception.message(e)}",
         code: "connector.execution_failed",
         upstream_context: %{"exception" => Exception.message(e)}
       )}
  catch
    kind, reason ->
      {:error,
       Error.new(:internal, "Connector execution failed: #{kind}",
         code: "connector.execution_failed",
         upstream_context: %{"reason" => inspect(reason)}
       )}
  end

  defp normalize_scope_error(%{missing_scopes: missing_scopes} = reason) do
    Error.new(:auth_failed, "Missing required scopes: #{Enum.join(missing_scopes, ", ")}",
      code: "auth.missing_scopes",
      upstream_context: stringify_keys(reason)
    )
  end

  defp normalize_scope_error(%{"missing_scopes" => missing_scopes} = reason) do
    Error.new(:auth_failed, "Missing required scopes: #{Enum.join(missing_scopes, ", ")}",
      code: "auth.missing_scopes",
      upstream_context: stringify_keys(reason)
    )
  end

  defp normalize_scope_error(reason) do
    Error.new(:auth_failed, "Scope validation failed",
      code: "auth.scope_check_failed",
      upstream_context: %{"reason" => inspect(reason)}
    )
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {to_string(key), stringify_keys(value)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp find_operation(manifest, operation_id) do
    Enum.find(manifest.operations, &(&1.id == operation_id))
  end

  defp auth_server_module, do: Jido.Integration.Auth.Server
end
