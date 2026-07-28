defmodule Jido.Integration.ProviderMaterializer do
  @moduledoc """
  Provider-local projection of redeemed Jido material into transient runtime authority.

  The public return value is transient and must remain inside
  `Jido.Integration.V2.Auth.with_materialized_credential/4`. Durable callers use
  redacted refs only.
  """

  alias Gemini.GovernedAuthority
  alias Gemini.GovernedAuthority.MaterializationRequest, as: GeminiMaterializationRequest
  alias Gemini.GovernedAuthority.SecretMaterial, as: GeminiSecretMaterial
  alias Jido.Integration.V2.Auth.ManagedAccount
  alias Jido.Integration.V2.CredentialLease
  alias Jido.Integration.V2.MaterializationRequest
  alias Jido.Integration.V2.SecretMaterial

  @required_binding_fields [
    :base_url,
    :provider_ref,
    :model_account_ref,
    :credential_handle_ref,
    :operation_policy_ref,
    :materialization_request
  ]

  @type binding :: %{
          required(:base_url) => String.t(),
          required(:provider_ref) => String.t(),
          required(:model_account_ref) => String.t(),
          required(:credential_handle_ref) => String.t(),
          required(:operation_policy_ref) => String.t(),
          required(:materialization_request) => MaterializationRequest.t(),
          optional(:redaction_ref) => String.t()
        }

  defmodule CodexRuntime do
    @moduledoc """
    Transient, inspect-redacted Codex runtime material owned by Jido.

    This value is valid only inside the managed credential callback that
    created it. It is consumed by ASM's exact managed-session admission and
    must never be persisted.
    """

    @enforce_keys [
      :command,
      :cwd,
      :env,
      :config_root,
      :credential_lease_ref,
      :native_auth_assertion_ref,
      :connector_binding_ref,
      :provider_account_ref,
      :native_auth_assertion
    ]
    @derive {Inspect,
             only: [
               :materialization_ref,
               :credential_generation,
               :credential_lease_ref,
               :native_auth_assertion_ref,
               :connector_binding_ref,
               :provider_account_ref,
               :workspace_ref,
               :source,
               :target_auth_posture
             ]}
    defstruct [
      :materialization_ref,
      :credential_generation,
      :command,
      :cwd,
      :env,
      :config_root,
      :credential_lease_ref,
      :native_auth_assertion_ref,
      :connector_binding_ref,
      :provider_account_ref,
      :workspace_ref,
      :native_auth_assertion,
      :api_key,
      :base_url,
      clear_env?: true,
      source: :verified_materializer,
      target_auth_posture: :materialize_on_attach
    ]

    @type t :: %__MODULE__{}
  end

  defmodule CodexBundle do
    @moduledoc """
    One transient Codex materialization plus its exact cleanup root.
    """

    @enforce_keys [:runtime, :secret_material, :cleanup_root, :cleanup_parent]
    @derive {Inspect, only: [:runtime]}
    defstruct [:runtime, :secret_material, :cleanup_root, :cleanup_parent]

    @type t :: %__MODULE__{}
  end

  @spec materialize(SecretMaterial.t(), binding()) ::
          {:ok, GovernedAuthority.t()} | {:error, term()}
  def materialize(%SecretMaterial{} = material, %{} = binding) do
    with :ok <- validate_binding(binding),
         %MaterializationRequest{} = request <- value(binding, :materialization_request),
         :ok <- validate_exact_agreement(material, request, binding),
         {:ok, api_key} <- api_key(material),
         {:ok, %GovernedAuthority{} = authority} <-
           build_authority(material, request, binding, api_key) do
      {:ok, authority}
    end
  rescue
    error in ArgumentError -> {:error, {:invalid_gemini_authority, Exception.message(error)}}
  end

  def materialize(_material, _binding), do: {:error, :invalid_provider_materialization}

  @spec authority_refs(GovernedAuthority.t()) :: {:ok, map()}
  def authority_refs(%GovernedAuthority{} = authority),
    do: {:ok, GovernedAuthority.refs(authority)}

  def authority_refs(_authority), do: {:error, :invalid_provider_authority}

  @doc """
  Materializes a redeemed Codex credential into one isolated config root.

  The command and root parent are trusted runtime configuration, not caller
  overrides. The workspace and all identity refs must already be pinned by the
  reviewed request and managed account.
  """
  @spec materialize_codex(
          SecretMaterial.t(),
          CredentialLease.t(),
          MaterializationRequest.t(),
          ManagedAccount.t(),
          map()
        ) :: {:ok, CodexBundle.t()} | {:error, term()}
  def materialize_codex(
        %SecretMaterial{} = material,
        %CredentialLease{} = lease,
        %MaterializationRequest{} = request,
        %ManagedAccount{} = account,
        binding
      )
      when is_map(binding) do
    with :ok <- validate_codex_identity(material, lease, request, account, binding),
         {:ok, command} <- configured_codex_command(),
         {:ok, cleanup_parent} <- configured_codex_root_parent(),
         {:ok, workspace_root} <- codex_workspace_root(binding),
         {:ok, config_root} <-
           create_codex_config_root(cleanup_parent, request.materialization_ref) do
      materialize_codex_in_root(
        config_root,
        cleanup_parent,
        command,
        workspace_root,
        material,
        lease,
        request,
        account,
        binding
      )
    else
      {:error, _reason} = error ->
        error
    end
  rescue
    error in [File.Error] -> {:error, {:codex_materialization_io_failed, error.reason}}
  end

  def materialize_codex(_material, _lease, _request, _account, _binding),
    do: {:error, :invalid_codex_materialization}

  defp materialize_codex_in_root(
         config_root,
         cleanup_parent,
         command,
         workspace_root,
         material,
         lease,
         request,
         account,
         binding
       ) do
    case install_codex_auth(config_root, material.payload) do
      {:ok, auth} ->
        runtime =
          build_codex_runtime(
            command,
            workspace_root,
            config_root,
            auth,
            lease,
            request,
            account,
            binding
          )

        {:ok,
         %CodexBundle{
           runtime: runtime,
           secret_material: %{material | payload: Map.from_struct(runtime)},
           cleanup_root: config_root,
           cleanup_parent: cleanup_parent
         }}

      {:error, _reason} = error ->
        _ = remove_codex_root(config_root, cleanup_parent)
        error
    end
  end

  @doc "Removes only the exact isolated config root created by `materialize_codex/5`."
  @spec cleanup_codex(CodexBundle.t()) :: :ok | {:error, term()}
  def cleanup_codex(%CodexBundle{} = bundle) do
    remove_codex_root(bundle.cleanup_root, bundle.cleanup_parent)
  end

  def cleanup_codex(_bundle), do: {:error, :invalid_codex_materialization_cleanup}

  defp validate_binding(binding) do
    missing = Enum.reject(@required_binding_fields, &present?(value(binding, &1)))

    case missing do
      [] -> :ok
      fields -> {:error, {:missing_provider_materialization_binding, fields}}
    end
  end

  defp validate_exact_agreement(material, request, binding) do
    account = request.account

    expected = [
      {material.materialization_ref, request.materialization_ref, :materialization_ref},
      {material.provider_family, account.provider_family, :provider_family},
      {material.account_ref, account.account_ref, :provider_account_ref},
      {material.generation, account.generation, :generation},
      {value(binding, :model_account_ref), account.account_ref, :model_account_ref},
      {value(binding, :endpoint_ref, request.endpoint_ref), request.endpoint_ref, :endpoint_ref},
      {value(binding, :authority_ref, request.authority_ref), request.authority_ref,
       :authority_ref},
      {value(binding, :operation_ref, request.operation_ref), request.operation_ref,
       :operation_ref},
      {value(binding, :target_ref, request.target_ref), request.target_ref, :target_ref},
      {value(binding, :fence, account.fence), account.fence, :fence}
    ]

    case Enum.find(expected, fn {actual, wanted, _field} -> actual != wanted end) do
      nil -> :ok
      {_actual, _wanted, field} -> {:error, {:provider_materialization_mismatch, field}}
    end
  end

  defp api_key(%SecretMaterial{payload: payload}) do
    case Map.get(payload, :api_key, Map.get(payload, "api_key")) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, :gemini_api_key_material_missing}
    end
  end

  defp build_authority(material, request, binding, api_key) do
    provider_request =
      GeminiMaterializationRequest.new!(%{
        materialization_ref: request.materialization_ref,
        lease_id: request.lease_id,
        account: Map.from_struct(request.account),
        effect_ref: request.effect_ref,
        operation_ref: request.operation_ref,
        authority_ref: request.authority_ref,
        endpoint_ref: request.endpoint_ref,
        target_ref: request.target_ref,
        issued_at: request.issued_at,
        expires_at: request.expires_at
      })

    provider_secret =
      GeminiSecretMaterial.new!(%{
        materialization_ref: material.materialization_ref,
        provider_family: material.provider_family,
        account_ref: material.account_ref,
        generation: material.generation,
        payload: %{headers: %{}, query_params: [{"key", api_key}]}
      })

    authority =
      GovernedAuthority.new!(%{
        base_url: value(binding, :base_url),
        provider_ref: value(binding, :provider_ref),
        model_account_ref: value(binding, :model_account_ref),
        credential_handle_ref: value(binding, :credential_handle_ref),
        operation_policy_ref: value(binding, :operation_policy_ref),
        redaction_ref: value(binding, :redaction_ref),
        headers: %{},
        materialization_request: provider_request,
        secret_material: provider_secret
      })

    {:ok, authority}
  end

  defp validate_codex_identity(material, lease, request, account, binding) do
    expected = [
      {material.materialization_ref, request.materialization_ref, :materialization_ref},
      {material.provider_family, "codex", :provider_family},
      {material.account_ref, account.account_ref, :account_ref},
      {material.generation, account.generation, :credential_generation},
      {request.account, ManagedAccount.ref(account), :managed_account_ref},
      {request.lease_id, lease.lease_id, :credential_lease_ref},
      {request.authority_ref, value(binding, :authority_ref), :authority_ref},
      {request.target_ref, value(binding, :target_ref), :target_ref},
      {request.operation_ref, value(binding, :operation_ref), :operation_ref}
    ]

    required_refs = [
      value(binding, :connector_binding_ref),
      value(binding, :native_auth_assertion_ref),
      value(binding, :workspace_ref),
      value(binding, :workspace_root),
      value(binding, :authority_ref),
      value(binding, :target_ref),
      value(binding, :operation_ref)
    ]

    cond do
      account.provider_family != "codex" ->
        {:error, :codex_managed_account_required}

      lease.tenant_id != account.tenant_id ->
        {:error, :codex_materialization_tenant_mismatch}

      Enum.any?(required_refs, &(not present?(&1))) ->
        {:error, :codex_materialization_binding_incomplete}

      mismatch = Enum.find(expected, fn {actual, wanted, _field} -> actual != wanted end) ->
        {_actual, _wanted, field} = mismatch
        {:error, {:codex_materialization_mismatch, field}}

      true ->
        :ok
    end
  end

  defp configured_codex_command do
    config = Application.get_env(:jido_integration_v2_control_plane, :codex_materializer, [])

    case Keyword.get(config, :command) do
      command when is_binary(command) and command != "" ->
        expanded = Path.expand(command)

        if Path.type(expanded) == :absolute and File.regular?(expanded),
          do: {:ok, expanded},
          else: {:error, :codex_materializer_command_unavailable}

      _missing ->
        {:error, :codex_materializer_command_not_configured}
    end
  end

  defp configured_codex_root_parent do
    config = Application.get_env(:jido_integration_v2_control_plane, :codex_materializer, [])

    case Keyword.get(config, :session_root_parent) do
      parent when is_binary(parent) and parent != "" ->
        parent = Path.expand(parent)

        if safe_root_parent?(parent) do
          case File.mkdir_p(parent) do
            :ok -> {:ok, parent}
            {:error, reason} -> {:error, {:codex_materializer_root_unavailable, reason}}
          end
        else
          {:error, :unsafe_codex_materializer_root}
        end

      _missing ->
        {:error, :codex_materializer_root_not_configured}
    end
  end

  defp safe_root_parent?(parent) do
    Path.type(parent) == :absolute and
      parent not in ["/", "/home", "/home/home", System.tmp_dir!()]
  end

  defp codex_workspace_root(binding) do
    case value(binding, :workspace_root) do
      root when is_binary(root) and root != "" ->
        root = Path.expand(root)

        if Path.type(root) == :absolute and File.dir?(root),
          do: {:ok, root},
          else: {:error, :codex_workspace_unavailable}

      _missing ->
        {:error, :codex_workspace_required}
    end
  end

  defp create_codex_config_root(parent, materialization_ref) do
    digest =
      :crypto.hash(
        :sha256,
        materialization_ref <> ":" <> Integer.to_string(System.unique_integer([:positive]))
      )
      |> Base.encode16(case: :lower)
      |> binary_part(0, 24)

    root = Path.join(parent, "jido-codex-" <> digest)

    with :ok <- validate_cleanup_root(root, parent),
         :ok <- File.mkdir(root),
         :ok <- File.chmod(root, 0o700) do
      {:ok, root}
    else
      {:error, reason} -> {:error, {:codex_materializer_root_create_failed, reason}}
    end
  end

  defp install_codex_auth(config_root, payload) when is_map(payload) do
    case {value(payload, :auth_json), value(payload, :api_key)} do
      {auth_json, nil} when not is_nil(auth_json) ->
        with {:ok, encoded} <- encode_auth_json(auth_json),
             :ok <-
               File.write(Path.join(config_root, "auth.json"), encoded, [:binary, :exclusive]),
             :ok <- File.chmod(Path.join(config_root, "auth.json"), 0o600) do
          {:ok, %{api_key: nil, env: %{"CODEX_HOME" => config_root}}}
        else
          {:error, reason} -> {:error, {:codex_auth_install_failed, reason}}
        end

      {nil, api_key} when is_binary(api_key) and api_key != "" ->
        {:ok,
         %{
           api_key: api_key,
           env: %{"CODEX_HOME" => config_root, "OPENAI_API_KEY" => api_key}
         }}

      _other ->
        {:error, :codex_secret_material_invalid}
    end
  end

  defp install_codex_auth(_config_root, _payload), do: {:error, :codex_secret_material_invalid}

  defp encode_auth_json(auth_json) when is_map(auth_json), do: Jason.encode(auth_json)

  defp encode_auth_json(auth_json) when is_binary(auth_json) and auth_json != "" do
    case Jason.decode(auth_json) do
      {:ok, %{} = decoded} -> Jason.encode(decoded)
      _other -> {:error, :invalid_auth_json}
    end
  end

  defp encode_auth_json(_auth_json), do: {:error, :invalid_auth_json}

  defp build_codex_runtime(
         command,
         workspace_root,
         config_root,
         auth,
         lease,
         request,
         account,
         binding
       ) do
    config = Application.get_env(:jido_integration_v2_control_plane, :codex_materializer, [])

    %CodexRuntime{
      materialization_ref: request.materialization_ref,
      credential_generation: account.generation,
      command: command,
      cwd: workspace_root,
      env: auth.env,
      config_root: config_root,
      credential_lease_ref: lease.lease_id,
      native_auth_assertion_ref: value(binding, :native_auth_assertion_ref),
      connector_binding_ref: value(binding, :connector_binding_ref),
      provider_account_ref: account.account_ref,
      workspace_ref: value(binding, :workspace_ref),
      native_auth_assertion: %{
        ref: value(binding, :native_auth_assertion_ref),
        introspection_level: :materialized_local,
        limits: %{
          account_ref: account.account_ref,
          credential_generation: account.generation,
          workspace_ref: value(binding, :workspace_ref),
          operation_ref: request.operation_ref
        },
        redacted?: true
      },
      api_key: auth.api_key,
      base_url: Keyword.get(config, :base_url),
      clear_env?: true,
      source: :verified_materializer,
      target_auth_posture: :materialize_on_attach
    }
  end

  defp validate_cleanup_root(root, parent)
       when is_binary(root) and is_binary(parent) do
    root = Path.expand(root)
    parent = Path.expand(parent)
    relative = Path.relative_to(root, parent)

    if Path.dirname(root) == parent and String.starts_with?(Path.basename(root), "jido-codex-") and
         relative != root and not String.starts_with?(relative, "..") do
      :ok
    else
      {:error, :unsafe_codex_materialization_cleanup}
    end
  end

  defp validate_cleanup_root(_root, _parent),
    do: {:error, :unsafe_codex_materialization_cleanup}

  defp remove_codex_root(root, parent) do
    with :ok <- validate_cleanup_root(root, parent) do
      case File.rm_rf(root) do
        {:ok, _paths} -> :ok
        {:error, _path, reason} -> {:error, {:codex_materialization_cleanup_failed, reason}}
      end
    end
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp present?(%MaterializationRequest{}), do: true
  defp present?(value) when is_binary(value), do: value != ""
  defp present?(_value), do: false
end
