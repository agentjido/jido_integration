defmodule Jido.Integration.Secrets.VaultKVProvider do
  @moduledoc """
  HashiCorp Vault KV v2 provider for production managed-account materialization.

  Callers supply an explicit Vault address and a transient token loader. The
  durable scope contains only mount/path and account references; neither the
  Vault token nor returned data enters a receipt or error.
  """

  @behaviour Jido.Integration.Secrets.Provider

  alias Jido.Integration.Secrets.SecretHandle

  @impl true
  def materialize(lease_ref, scope, opts)
      when is_binary(lease_ref) and is_map(scope) and is_list(opts) do
    with {:ok, address} <- address(opts),
         {:ok, mount} <- required_scope(scope, :mount),
         {:ok, path} <- required_scope(scope, :path),
         {:ok, token} <- token(opts),
         {:ok, response} <- request(:get, kv_url(address, mount, path), token, opts),
         {:ok, material, metadata} <- decode_kv_response(response) do
      provider_ref = "vault-kv-v2://#{mount}/#{path}"

      SecretHandle.new(
        lease_ref: lease_ref,
        provider_ref: provider_ref,
        audit_ref: audit_ref(%{lease_ref: lease_ref, provider_ref: provider_ref}),
        material: select_material(material, scope),
        scope: Map.drop(scope, [:material, "material"]),
        metadata: metadata
      )
    end
  end

  def materialize(_lease_ref, _scope, _opts), do: {:error, :invalid_vault_materialization}

  @doc false
  @spec managed_scope(map(), map(), map()) :: {:ok, map()} | {:error, term()}
  def managed_scope(account, lease, _request)
      when is_map(account) and is_map(lease) do
    with {:ok, provider_uri} <- parse_managed_uri(value(account, :secret_provider_ref)),
         {:ok, binding_uri} <- parse_managed_uri(value(account, :secret_binding_ref)),
         :ok <- validate_managed_uri(provider_uri, "vault", :secret_provider_ref),
         :ok <- validate_managed_uri(binding_uri, "vault-secret", :secret_binding_ref),
         true <- provider_uri.path == "/kv-v2" or {:error, :unsupported_vault_engine},
         {:ok, path} <- binding_path(binding_uri) do
      {:ok,
       %{
         mount: provider_uri.host,
         path: path,
         fields: Map.get(lease, :lease_fields, Map.get(lease, "lease_fields", []))
       }}
    end
  end

  def managed_scope(_account, _lease, _request), do: {:error, :invalid_vault_binding}

  @spec probe(keyword()) :: {:ok, map()} | {:error, term()}
  def probe(opts) when is_list(opts) do
    with {:ok, address} <- address(opts),
         {:ok, token} <- token(opts),
         {:ok, %{status: status}} <- request(:get, address <> "/v1/sys/health", token, opts) do
      if status == 200 do
        {:ok, %{provider: :hashicorp_vault, ready?: true, endpoint_ref: endpoint_ref(address)}}
      else
        {:error, {:vault_not_ready, status}}
      end
    end
  end

  @impl true
  def rotate(binding_ref, opts) when is_binary(binding_ref) and is_list(opts) do
    case Keyword.get(opts, :next_binding_ref) do
      next when is_binary(next) and next != "" ->
        {:ok,
         %{
           binding_ref: binding_ref,
           next_binding_ref: next,
           status: :rotation_requested,
           audit_ref: audit_ref(%{binding_ref: binding_ref, next_binding_ref: next})
         }}

      _missing ->
        {:error, :next_binding_ref_required}
    end
  end

  @impl true
  def revoke(lease_ref, _opts) when is_binary(lease_ref) do
    {:ok,
     %{
       lease_ref: lease_ref,
       status: :materialization_scope_closed,
       audit_ref: audit_ref(%{lease_ref: lease_ref, operation: :close})
     }}
  end

  @impl true
  def audit_ref(%SecretHandle{} = handle), do: handle.audit_ref

  def audit_ref(attrs) when is_map(attrs) do
    digest = :crypto.hash(:sha256, :erlang.term_to_binary(attrs)) |> Base.encode16(case: :lower)
    "secret-audit://vault-kv-v2/#{digest}"
  end

  defp address(opts) do
    case Keyword.get(opts, :address) do
      address when is_binary(address) and address != "" ->
        uri = URI.parse(String.trim_trailing(address, "/"))

        if uri.scheme == "https" and is_binary(uri.host),
          do: {:ok, URI.to_string(uri)},
          else: {:error, :invalid_vault_address}

      _missing ->
        {:error, :vault_address_required}
    end
  end

  defp token(opts) do
    case Keyword.get(opts, :token_loader) do
      loader when is_function(loader, 0) -> normalize_token(loader.())
      _missing -> {:error, :vault_token_loader_required}
    end
  end

  defp normalize_token({:ok, token}), do: normalize_token(token)
  defp normalize_token({:error, _reason}), do: {:error, :vault_token_unavailable}
  defp normalize_token(token) when is_binary(token) and token != "", do: {:ok, token}
  defp normalize_token(_token), do: {:error, :vault_token_unavailable}

  defp required_scope(scope, key) do
    case value(scope, key) do
      value when is_binary(value) and value != "" ->
        if String.contains?(value, ".."),
          do: {:error, {:invalid_vault_scope, key}},
          else: {:ok, String.trim(value, "/")}

      _missing ->
        {:error, {:invalid_vault_scope, key}}
    end
  end

  defp validate_managed_uri(uri, scheme, field) do
    if uri.scheme == scheme and present_string?(uri.host) and is_nil(uri.userinfo) and
         is_nil(uri.query) and is_nil(uri.fragment),
       do: :ok,
       else: {:error, {:invalid_vault_binding, field}}
  end

  defp parse_managed_uri(value) when is_binary(value) and value != "",
    do: {:ok, URI.parse(value)}

  defp parse_managed_uri(_value), do: {:error, :invalid_vault_binding}

  defp binding_path(uri) do
    path = Enum.join([uri.host, String.trim(uri.path || "", "/")], "/")

    if present_string?(path) and not String.contains?(path, ".."),
      do: {:ok, path},
      else: {:error, {:invalid_vault_binding, :secret_binding_ref}}
  end

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp request(method, url, token, opts) do
    client = Keyword.get(opts, :http_client, __MODULE__.Httpc)

    headers =
      [{"x-vault-token", token}]
      |> maybe_namespace(Keyword.get(opts, :namespace))

    try do
      case client.request(method, url, headers, Keyword.get(opts, :http_options, [])) do
        {:ok, %{status: status} = response} when status in 200..299 -> {:ok, response}
        {:ok, %{status: status}} -> {:error, {:vault_request_failed, status}}
        {:error, _reason} -> {:error, :vault_unavailable}
        _other -> {:error, :invalid_vault_response}
      end
    rescue
      _exception -> {:error, :vault_unavailable}
    catch
      _kind, _reason -> {:error, :vault_unavailable}
    end
  end

  defp decode_kv_response(%{body: body}) when is_binary(body) do
    with {:ok, %{"data" => %{"data" => material} = envelope}} <- Jason.decode(body),
         true <- is_map(material) and map_size(material) > 0 do
      metadata =
        envelope
        |> Map.get("metadata", %{})
        |> Map.take(["created_time", "deletion_time", "destroyed", "version"])
        |> Map.put("source", "vault_kv_v2")

      {:ok, material, metadata}
    else
      _other -> {:error, :invalid_vault_kv_response}
    end
  end

  defp select_material(material, scope) do
    case value(scope, :fields) do
      fields when is_list(fields) and fields != [] ->
        fields = MapSet.new(Enum.map(fields, &to_string/1))

        Map.new(material, fn {key, value} -> {key, value} end)
        |> Map.filter(fn {key, _value} -> MapSet.member?(fields, to_string(key)) end)

      _all ->
        material
    end
  end

  defp maybe_namespace(headers, namespace) when is_binary(namespace) and namespace != "",
    do: [{"x-vault-namespace", namespace} | headers]

  defp maybe_namespace(headers, _namespace), do: headers

  defp kv_url(address, mount, path),
    do: address <> "/v1/" <> URI.encode(mount) <> "/data/" <> encode_path(path)

  defp encode_path(path), do: path |> String.split("/") |> Enum.map_join("/", &URI.encode/1)

  defp endpoint_ref(address),
    do: "endpoint://vault/" <> Base.url_encode64(address, padding: false)

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defmodule Httpc do
    @moduledoc false

    def request(method, url, headers, opts) do
      request = {String.to_charlist(url), encode_headers(headers)}
      http_opts = Keyword.merge([ssl: tls_options(url)], opts)

      case :httpc.request(method, request, http_opts, body_format: :binary) do
        {:ok, {{_version, status, _reason}, _headers, body}} ->
          {:ok, %{status: status, body: body}}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp encode_headers(headers) do
      Enum.map(headers, fn {key, value} ->
        {String.to_charlist(key), String.to_charlist(value)}
      end)
    end

    defp tls_options(url) do
      host = URI.parse(url).host

      [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(host),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    end
  end
end
