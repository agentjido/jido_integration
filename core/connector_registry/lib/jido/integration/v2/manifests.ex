defmodule Jido.Integration.V2.Manifests do
  @moduledoc """
  Credential-free connector manifest lookup and operation descriptor resolution.
  """

  alias Jido.Integration.V2.Capability
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.Manifest
  alias Jido.Integration.V2.ManifestRegistry
  alias Jido.Integration.V2.OperationDescriptor
  alias Jido.Integration.V2.OperationLookupRequest
  alias Jido.Integration.V2.OperationSpec

  @behaviour ManifestRegistry

  @impl true
  def fetch_connector_manifest(connector_ref, opts \\ []) do
    connector_ref = Contracts.validate_non_empty_string!(connector_ref, "connector_ref")

    case registry_backend(opts) do
      nil -> fetch_connector_manifest_from_entries(connector_ref, opts)
      backend -> backend.fetch_connector_manifest(connector_ref, opts)
    end
  end

  @impl true
  def fetch_operation(connector_ref, operation_ref, opts \\ []) do
    operation_ref = Contracts.validate_non_empty_string!(operation_ref, "operation_ref")

    with {:ok, entry} <- fetch_connector_manifest(connector_ref, opts) do
      case Manifest.fetch_operation(entry.manifest, operation_ref) do
        %OperationSpec{} = operation -> {:ok, entry.manifest, operation}
        nil -> {:error, {:operation_ref_missing, connector_ref, operation_ref}}
      end
    end
  end

  def resolve_operation(request, opts \\ [])

  @impl true
  def resolve_operation(%OperationLookupRequest{} = request, opts) do
    with {:ok, request} <- OperationLookupRequest.new(request),
         {:ok, entry} <- fetch_connector_manifest(request.connector_ref, opts),
         :ok <- verify_requested_manifest_ref(request, entry),
         :ok <- verify_manifest_digest(request, entry),
         {:ok, operation} <- fetch_entry_operation(entry, request.operation_ref),
         {:ok, descriptor} <- descriptor_from(entry, operation, request),
         :ok <- verify_operation_class(request, descriptor),
         :ok <- verify_binding_kind(request, descriptor),
         :ok <- verify_runtime_family(request, descriptor),
         :ok <- verify_credential_scope(request, entry) do
      {:ok, descriptor}
    end
  end

  def resolve_operation(attrs, opts) when is_map(attrs) or is_list(attrs) do
    with {:ok, request} <- OperationLookupRequest.new(attrs) do
      resolve_operation(request, opts)
    end
  end

  @spec verify_dependency(OperationDescriptor.t() | OperationLookupRequest.t() | map(), keyword()) ::
          {:ok, :exact | {:compatible, OperationDescriptor.t()}}
          | {:ok, OperationDescriptor.t()}
          | {:error, term()}
  def verify_dependency(dependency, opts \\ [])

  def verify_dependency(%OperationLookupRequest{} = request, opts) do
    resolve_operation(request, opts)
  end

  def verify_dependency(%OperationDescriptor{} = compiled_descriptor, opts) do
    request =
      OperationLookupRequest.new!(%{
        connector_ref: compiled_descriptor.connector_ref,
        manifest_ref: compiled_descriptor.manifest_ref,
        operation_ref: compiled_descriptor.operation_ref,
        operation_role: compiled_descriptor.operation_role,
        operation_class: compiled_descriptor.operation_class,
        binding_kind: compiled_descriptor.binding_kind,
        required_runtime_family: compiled_descriptor.runtime_family,
        binding_ref:
          Contracts.get(compiled_descriptor.metadata, :binding_ref, "binding://compiled"),
        pack_ref: Contracts.get(compiled_descriptor.metadata, :pack_ref, "pack://compiled"),
        pack_revision: Contracts.get(compiled_descriptor.metadata, :pack_revision, "compiled"),
        credential_scope_ref: compiled_descriptor.credential_scope_ref
      })

    with {:ok, current_descriptor} <- resolve_operation(request, opts),
         :ok <- verify_side_effect_stability(compiled_descriptor, current_descriptor),
         :ok <- verify_scope_stability(compiled_descriptor, current_descriptor) do
      if compiled_descriptor.manifest_digest == current_descriptor.manifest_digest do
        {:ok, :exact}
      else
        {:ok, {:compatible, current_descriptor}}
      end
    end
  end

  def verify_dependency(attrs, opts) when is_map(attrs) or is_list(attrs) do
    with {:ok, request} <- OperationLookupRequest.new(attrs) do
      verify_dependency(request, opts)
    end
  end

  defp fetch_connector_manifest_from_entries(connector_ref, opts) do
    opts
    |> manifest_entries()
    |> Enum.find(fn entry -> entry.connector_ref == connector_ref end)
    |> case do
      nil -> {:error, {:connector_manifest_missing, connector_ref}}
      entry -> {:ok, entry}
    end
  end

  defp fetch_entry_operation(%ManifestRegistry.Entry{} = entry, operation_ref) do
    case Manifest.fetch_operation(entry.manifest, operation_ref) do
      %OperationSpec{} = operation -> {:ok, operation}
      nil -> {:error, {:operation_ref_missing, entry.connector_ref, operation_ref}}
    end
  end

  defp descriptor_from(%ManifestRegistry.Entry{} = entry, %OperationSpec{} = operation, request) do
    capability = Capability.from_operation!(entry.manifest.connector, operation)

    OperationDescriptor.new(%{
      operation_manifest_ref: operation_manifest_ref(entry.manifest_ref, operation.operation_id),
      connector_ref: entry.connector_ref,
      manifest_ref: entry.manifest_ref,
      operation_ref: operation.operation_id,
      operation_role: request.operation_role,
      operation_class: operation_class(operation, capability),
      binding_kind: entry.manifest.auth.binding_kind,
      side_effect_class: Contracts.get(capability.metadata, :side_effect_class),
      input_schema_ref: schema_ref(operation, :input_schema_ref, "input"),
      output_schema_ref: schema_ref(operation, :output_schema_ref, "output"),
      credential_scope_ref: request.credential_scope_ref,
      runtime_family: operation.runtime_class,
      manifest_digest: entry.manifest_digest,
      required_scopes: Capability.required_scopes(capability),
      provider_family: entry.provider_family,
      provider_operation_id: provider_operation_id(operation),
      connector_version: entry.connector_version,
      adapter_ref: entry.adapter_ref,
      handler_ref: inspect(operation.handler),
      metadata:
        Map.merge(entry.metadata, %{
          binding_ref: request.binding_ref,
          pack_ref: request.pack_ref,
          pack_revision: request.pack_revision,
          manifest_connector: entry.manifest.connector
        })
    })
  end

  defp operation_class(%OperationSpec{} = operation, %Capability{} = capability) do
    Contracts.get(operation.metadata, :operation_class) ||
      Contracts.get(capability.metadata, :operation_class) ||
      :connector_operation
  end

  defp provider_operation_id(%OperationSpec{} = operation) do
    Contracts.get(operation.metadata, :provider_operation_id, operation.operation_id)
  end

  defp schema_ref(%OperationSpec{} = operation, metadata_key, suffix) do
    Contracts.get(operation.metadata, metadata_key) || operation.operation_id <> ":" <> suffix
  end

  defp verify_requested_manifest_ref(%OperationLookupRequest{} = request, entry) do
    if request.manifest_ref == entry.manifest_ref do
      :ok
    else
      {:error, {:connector_manifest_missing, request.connector_ref}}
    end
  end

  defp verify_manifest_digest(%OperationLookupRequest{compiled_manifest_hash: nil}, _entry),
    do: :ok

  defp verify_manifest_digest(%OperationLookupRequest{} = request, entry) do
    if request.compiled_manifest_hash == entry.manifest_digest do
      :ok
    else
      {:error,
       {:manifest_digest_mismatch, request.binding_ref, request.compiled_manifest_hash,
        entry.manifest_digest}}
    end
  end

  defp verify_operation_class(
         %OperationLookupRequest{} = request,
         %OperationDescriptor{} = descriptor
       ) do
    if request.operation_class == descriptor.operation_class do
      :ok
    else
      {:error,
       {:operation_class_mismatch, request.operation_ref, request.operation_class,
        descriptor.operation_class}}
    end
  end

  defp verify_binding_kind(
         %OperationLookupRequest{} = request,
         %OperationDescriptor{} = descriptor
       ) do
    if request.binding_kind == descriptor.binding_kind do
      :ok
    else
      {:error,
       {:binding_kind_mismatch, request.operation_ref, request.binding_kind,
        descriptor.binding_kind}}
    end
  end

  defp verify_runtime_family(
         %OperationLookupRequest{} = request,
         %OperationDescriptor{} = descriptor
       ) do
    if request.required_runtime_family == descriptor.runtime_family do
      :ok
    else
      {:error,
       {:runtime_family_mismatch, request.operation_ref, request.required_runtime_family,
        descriptor.runtime_family}}
    end
  end

  defp verify_credential_scope(
         %OperationLookupRequest{} = request,
         %ManifestRegistry.Entry{} = entry
       ) do
    case Contracts.get(entry.metadata, :credential_scope_ref) do
      nil ->
        :ok

      credential_scope_ref when credential_scope_ref == request.credential_scope_ref ->
        :ok

      credential_scope_ref ->
        {:error,
         {:credential_scope_mismatch, request.operation_ref, request.credential_scope_ref,
          credential_scope_ref}}
    end
  end

  defp verify_side_effect_stability(compiled, current) do
    if compiled.side_effect_class == current.side_effect_class do
      :ok
    else
      {:error, {:side_effect_class_expanded_since_compile, compiled.operation_ref}}
    end
  end

  defp verify_scope_stability(compiled, current) do
    expanded_scopes = current.required_scopes -- compiled.required_scopes

    if expanded_scopes == [] do
      :ok
    else
      {:error, {:operation_scope_expanded_since_compile, compiled.operation_ref}}
    end
  end

  defp manifest_entries(opts) do
    opts
    |> Keyword.get(:manifest_entries, Keyword.get(opts, :manifests, []))
    |> normalize_entries()
  end

  defp normalize_entries(entries) when is_list(entries) do
    Enum.map(entries, &ManifestRegistry.Entry.new!/1)
  end

  defp normalize_entries(entries) when is_map(entries) do
    Enum.map(entries, fn {connector_ref, entry_or_manifest} ->
      case entry_or_manifest do
        %ManifestRegistry.Entry{} = entry -> entry
        manifest -> ManifestRegistry.Entry.new!(connector_ref: connector_ref, manifest: manifest)
      end
    end)
  end

  defp normalize_entries(nil), do: []

  defp registry_backend(opts) do
    case Keyword.get(opts, :registry) do
      nil ->
        nil

      __MODULE__ ->
        nil

      backend when is_atom(backend) ->
        backend

      _other ->
        nil
    end
  end

  defp operation_manifest_ref(manifest_ref, operation_id) do
    manifest_ref <> "#operation:" <> operation_id
  end
end
