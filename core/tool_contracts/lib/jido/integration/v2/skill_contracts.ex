defmodule Jido.Integration.V2.SkillContracts do
  @moduledoc """
  Governed skill package contracts.

  These contracts model skill packages as policy-owned data. They reject
  runtime-local script paths, ambient credentials, and raw payload material.
  """

  @package_fields [
    :skill_ref,
    :package_name,
    :version,
    :manifest_hash,
    :description,
    :entrypoints,
    :allowed_artifact_posture,
    :credential_posture,
    :allowed_runtime_families,
    :policy_refs,
    :docs_ref,
    :tenant_ref,
    :installation_ref,
    :capability_refs,
    :trace_ref,
    :release_manifest_ref,
    :redaction_posture
  ]

  @entrypoint_fields [:name, :kind, :schema_ref, :capability_ref]

  @intent_fields [
    :invocation_ref,
    :skill_ref,
    :tenant_ref,
    :authority_ref,
    :idempotency_key,
    :entrypoint_name,
    :credential_lease_ref,
    :target_ref,
    :trace_ref,
    :input_ref
  ]

  @envelope_option_fields [:policy_projection_ref, :receipt_ledger_ref]

  @entrypoint_kinds [:jido_action, :connector_capability, :runtime_capability]
  @artifact_postures [:claim_checked]
  @credential_postures [:lease_required, :no_credentials]
  @runtime_families [:direct, :process, :session, :http, :jsonrpc, :interop]
  @redaction_postures [:refs_only, :private_state_redacted]

  @forbidden_keys [
    :api_key,
    :auth_header,
    :authorization,
    :authorization_header,
    :body,
    :command,
    :content,
    :cookie,
    :credential,
    :credential_material,
    :credential_payload,
    :credentials,
    :cwd,
    :endpoint,
    :endpoint_url,
    :env,
    :path,
    :password,
    :private_key,
    :provider_payload,
    :raw_authorization,
    :raw_body,
    :raw_content,
    :raw_credential,
    :raw_endpoint,
    :raw_endpoint_url,
    :raw_secret,
    :raw_token,
    :script_path,
    :secret,
    :session_cookie,
    :shell_args,
    :token,
    :url,
    :uri
  ]

  defmodule SkillPackage do
    @moduledoc "Governed skill package manifest."

    @enforce_keys [
      :skill_ref,
      :package_name,
      :version,
      :manifest_hash,
      :description,
      :entrypoints,
      :allowed_artifact_posture,
      :credential_posture,
      :allowed_runtime_families,
      :policy_refs,
      :docs_ref,
      :tenant_ref,
      :installation_ref,
      :capability_refs,
      :trace_ref,
      :release_manifest_ref,
      :redaction_posture
    ]
    defstruct @enforce_keys

    @type entrypoint :: %{
            required(:name) => String.t(),
            required(:kind) => atom(),
            required(:schema_ref) => String.t(),
            optional(:capability_ref) => String.t()
          }

    @type t :: %__MODULE__{
            skill_ref: String.t(),
            package_name: String.t(),
            version: String.t(),
            manifest_hash: String.t(),
            description: String.t(),
            entrypoints: [entrypoint(), ...],
            allowed_artifact_posture: atom(),
            credential_posture: atom(),
            allowed_runtime_families: [atom(), ...],
            policy_refs: [String.t(), ...],
            docs_ref: String.t(),
            tenant_ref: String.t(),
            installation_ref: String.t(),
            capability_refs: [String.t()],
            trace_ref: String.t(),
            release_manifest_ref: String.t(),
            redaction_posture: atom()
          }
  end

  defmodule SkillInvocationIntent do
    @moduledoc "Governed skill invocation intent."

    @enforce_keys [
      :invocation_ref,
      :skill_ref,
      :tenant_ref,
      :authority_ref,
      :idempotency_key,
      :entrypoint_name,
      :target_ref,
      :trace_ref,
      :input_ref
    ]
    defstruct @enforce_keys ++ [credential_lease_ref: nil]

    @type t :: %__MODULE__{
            invocation_ref: String.t(),
            skill_ref: String.t(),
            tenant_ref: String.t(),
            authority_ref: String.t(),
            idempotency_key: String.t(),
            entrypoint_name: String.t(),
            credential_lease_ref: String.t() | nil,
            target_ref: String.t(),
            trace_ref: String.t(),
            input_ref: String.t()
          }
  end

  defmodule SkillInvocationEnvelope do
    @moduledoc "Authority-bound lower skill invocation envelope."

    @enforce_keys [
      :invocation_ref,
      :skill_ref,
      :tenant_ref,
      :authority_ref,
      :policy_projection_ref,
      :receipt_ledger_ref,
      :idempotency_key,
      :entrypoint,
      :target_ref,
      :trace_ref,
      :input_ref,
      :raw_material_present?
    ]
    defstruct @enforce_keys ++ [credential_lease_ref: nil]

    @type t :: %__MODULE__{
            invocation_ref: String.t(),
            skill_ref: String.t(),
            tenant_ref: String.t(),
            authority_ref: String.t(),
            policy_projection_ref: String.t(),
            receipt_ledger_ref: String.t(),
            idempotency_key: String.t(),
            entrypoint: SkillPackage.entrypoint(),
            credential_lease_ref: String.t() | nil,
            target_ref: String.t(),
            trace_ref: String.t(),
            input_ref: String.t(),
            raw_material_present?: false
          }
  end

  @type package_attrs :: map() | keyword() | SkillPackage.t()
  @type intent_attrs :: map() | keyword() | SkillInvocationIntent.t()

  @spec package(package_attrs()) :: {:ok, SkillPackage.t()} | {:error, term()}
  def package(%SkillPackage{} = package), do: {:ok, package}

  def package(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_forbidden(attrs, :skill_package),
         :ok <- reject_unknown(attrs, @package_fields, :skill_package),
         {:ok, manifest_hash} <- required(attrs, :manifest_hash),
         :ok <- verify_manifest_hash(attrs, manifest_hash),
         {:ok, entrypoints} <- entrypoints(value(attrs, :entrypoints)),
         {:ok, allowed_runtime_families} <-
           non_empty_enum_list(attrs, :allowed_runtime_families, @runtime_families),
         {:ok, policy_refs} <- non_empty_string_list(attrs, :policy_refs),
         {:ok, capability_refs} <- string_list(attrs, :capability_refs, []) do
      {:ok,
       %SkillPackage{
         skill_ref: string!(attrs, :skill_ref),
         package_name: string!(attrs, :package_name),
         version: string!(attrs, :version),
         manifest_hash: manifest_hash,
         description: string!(attrs, :description),
         entrypoints: entrypoints,
         allowed_artifact_posture: enum!(attrs, :allowed_artifact_posture, @artifact_postures),
         credential_posture: enum!(attrs, :credential_posture, @credential_postures),
         allowed_runtime_families: allowed_runtime_families,
         policy_refs: policy_refs,
         docs_ref: string!(attrs, :docs_ref),
         tenant_ref: string!(attrs, :tenant_ref),
         installation_ref: string!(attrs, :installation_ref),
         capability_refs: capability_refs,
         trace_ref: string!(attrs, :trace_ref),
         release_manifest_ref: string!(attrs, :release_manifest_ref),
         redaction_posture: enum!(attrs, :redaction_posture, @redaction_postures)
       }}
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec package!(package_attrs()) :: SkillPackage.t()
  def package!(attrs) do
    case package(attrs) do
      {:ok, package} -> package
      {:error, error} -> raise error
    end
  end

  @spec canonical_manifest_hash(package_attrs()) :: String.t()
  def canonical_manifest_hash(attrs) do
    attrs =
      attrs
      |> normalize()
      |> Map.delete(:manifest_hash)
      |> Map.delete("manifest_hash")

    digest =
      :sha256
      |> :crypto.hash(:erlang.term_to_binary(stable(attrs)))
      |> Base.encode16(case: :lower)

    "sha256:" <> digest
  end

  @spec invocation_intent(intent_attrs()) ::
          {:ok, SkillInvocationIntent.t()} | {:error, term()}
  def invocation_intent(%SkillInvocationIntent{} = intent), do: {:ok, intent}

  def invocation_intent(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_forbidden(attrs, :skill_invocation),
         :ok <- reject_unknown(attrs, @intent_fields, :skill_invocation) do
      {:ok,
       %SkillInvocationIntent{
         invocation_ref: string!(attrs, :invocation_ref),
         skill_ref: string!(attrs, :skill_ref),
         tenant_ref: string!(attrs, :tenant_ref),
         authority_ref: string!(attrs, :authority_ref),
         idempotency_key: string!(attrs, :idempotency_key),
         entrypoint_name: string!(attrs, :entrypoint_name),
         credential_lease_ref: optional_string(attrs, :credential_lease_ref),
         target_ref: string!(attrs, :target_ref),
         trace_ref: string!(attrs, :trace_ref),
         input_ref: string!(attrs, :input_ref)
       }}
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec invocation_intent!(intent_attrs()) :: SkillInvocationIntent.t()
  def invocation_intent!(attrs) do
    case invocation_intent(attrs) do
      {:ok, intent} -> intent
      {:error, error} -> raise error
    end
  end

  @spec invocation_envelope(SkillPackage.t(), SkillInvocationIntent.t(), map() | keyword()) ::
          {:ok, SkillInvocationEnvelope.t()} | {:error, term()}
  def invocation_envelope(%SkillPackage{} = package, %SkillInvocationIntent{} = intent, opts) do
    opts = normalize(opts)

    with :ok <- reject_unknown(opts, @envelope_option_fields, :skill_invocation_envelope),
         :ok <- same_skill(package, intent),
         {:ok, entrypoint} <- entrypoint_by_name(package, intent.entrypoint_name),
         :ok <- credential_posture_allowed(package, intent) do
      {:ok,
       %SkillInvocationEnvelope{
         invocation_ref: intent.invocation_ref,
         skill_ref: intent.skill_ref,
         tenant_ref: intent.tenant_ref,
         authority_ref: intent.authority_ref,
         policy_projection_ref: string!(opts, :policy_projection_ref),
         receipt_ledger_ref: string!(opts, :receipt_ledger_ref),
         idempotency_key: intent.idempotency_key,
         entrypoint: entrypoint,
         credential_lease_ref: intent.credential_lease_ref,
         target_ref: intent.target_ref,
         trace_ref: intent.trace_ref,
         input_ref: intent.input_ref,
         raw_material_present?: false
       }}
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  @spec projection(SkillPackage.t()) :: map()
  def projection(%SkillPackage{} = package) do
    %{
      skill_ref: package.skill_ref,
      version_ref: "skill-version://#{package.package_name}/#{package.version}",
      revision: 1,
      tenant_ref: package.tenant_ref,
      installation_ref: package.installation_ref,
      package_name: package.package_name,
      version: package.version,
      manifest_hash: package.manifest_hash,
      policy_refs: package.policy_refs,
      capability_refs: package.capability_refs,
      docs_ref: package.docs_ref,
      trace_ref: package.trace_ref,
      release_manifest_ref: package.release_manifest_ref,
      redaction_posture: Atom.to_string(package.redaction_posture),
      admission_status: :admitted
    }
  end

  @spec trace_projection(SkillPackage.t()) :: map()
  def trace_projection(%SkillPackage{} = package) do
    %{
      trace_ref: package.trace_ref,
      skill_ref: package.skill_ref,
      manifest_hash: package.manifest_hash,
      policy_refs: package.policy_refs,
      capability_refs: package.capability_refs,
      release_manifest_ref: package.release_manifest_ref,
      redaction_posture: Atom.to_string(package.redaction_posture)
    }
  end

  defp verify_manifest_hash(attrs, manifest_hash) do
    expected = canonical_manifest_hash(attrs)

    if manifest_hash == expected do
      :ok
    else
      {:error, {:manifest_hash_mismatch, %{expected: expected, got: manifest_hash}}}
    end
  end

  defp entrypoints(value) when is_list(value) and value != [] do
    value
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, acc} ->
      case entrypoint(attrs) do
        {:ok, entrypoint} -> {:cont, {:ok, [entrypoint | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entrypoints} -> {:ok, Enum.reverse(entrypoints)}
      error -> error
    end
  end

  defp entrypoints(_value), do: {:error, invalid(:entrypoints, "must be a non-empty list")}

  defp entrypoint(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with :ok <- reject_forbidden(attrs, :skill_package),
         :ok <- reject_unknown(attrs, @entrypoint_fields, :skill_entrypoint) do
      entrypoint = %{
        name: string!(attrs, :name),
        kind: enum!(attrs, :kind, @entrypoint_kinds),
        schema_ref: string!(attrs, :schema_ref)
      }

      {:ok, optional_put(entrypoint, :capability_ref, optional_string(attrs, :capability_ref))}
    end
  rescue
    error in ArgumentError -> {:error, error}
  end

  defp same_skill(%SkillPackage{skill_ref: skill_ref}, %SkillInvocationIntent{
         skill_ref: skill_ref
       }),
       do: :ok

  defp same_skill(%SkillPackage{skill_ref: package_ref}, %SkillInvocationIntent{
         skill_ref: intent_ref
       }) do
    {:error, {:skill_ref_mismatch, %{package: package_ref, intent: intent_ref}}}
  end

  defp entrypoint_by_name(%SkillPackage{} = package, name) do
    case Enum.find(package.entrypoints, &(&1.name == name)) do
      nil -> {:error, {:unknown_skill_entrypoint, name}}
      entrypoint -> {:ok, entrypoint}
    end
  end

  defp credential_posture_allowed(
         %SkillPackage{credential_posture: :lease_required},
         %SkillInvocationIntent{credential_lease_ref: nil}
       ) do
    {:error, :credential_lease_required}
  end

  defp credential_posture_allowed(
         %SkillPackage{credential_posture: :no_credentials},
         %SkillInvocationIntent{credential_lease_ref: lease_ref}
       )
       when is_binary(lease_ref) do
    {:error, :credential_lease_not_allowed}
  end

  defp credential_posture_allowed(_package, _intent), do: :ok

  defp reject_unknown(attrs, fields, context) do
    unknown =
      attrs
      |> Map.keys()
      |> Enum.map(&normalize_key/1)
      |> Enum.reject(&(&1 in fields))

    case unknown do
      [] -> :ok
      fields -> {:error, {:"unknown_#{context}_fields", fields}}
    end
  end

  defp reject_forbidden(value, context), do: reject_forbidden(value, context, [])

  defp reject_forbidden(%_{} = value, context, path) do
    value
    |> Map.from_struct()
    |> reject_forbidden(context, path)
  end

  defp reject_forbidden(%{} = value, context, path) do
    Enum.reduce_while(value, :ok, fn {key, nested_value}, :ok ->
      reject_forbidden_entry(key, nested_value, context, path)
    end)
  end

  defp reject_forbidden(values, context, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      nested_forbidden_result(value, context, [index | path])
    end)
  end

  defp reject_forbidden(_value, _context, _path), do: :ok

  defp reject_forbidden_entry(key, nested_value, context, path) do
    normalized = normalize_key(key)

    if normalized in @forbidden_keys do
      {:halt, {:error, {:"forbidden_#{context}_fields", Enum.reverse([normalized | path])}}}
    else
      nested_forbidden_result(nested_value, context, [normalized | path])
    end
  end

  defp nested_forbidden_result(value, context, path) when is_map(value) or is_list(value) do
    case reject_forbidden(value, context, path) do
      :ok -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp nested_forbidden_result(_value, _context, _path), do: {:cont, :ok}

  defp required(attrs, field) do
    case value(attrs, field) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, invalid(field, "is required")}
    end
  end

  defp string!(attrs, field) do
    case value(attrs, field) do
      value when is_binary(value) and value != "" -> value
      other -> raise invalid(field, "must be a non-empty string, got: #{inspect(other)}")
    end
  end

  defp optional_string(attrs, field) do
    case value(attrs, field) do
      nil -> nil
      value when is_binary(value) and value != "" -> value
      other -> raise invalid(field, "must be a non-empty string, got: #{inspect(other)}")
    end
  end

  defp enum!(attrs, field, allowed) do
    value = value(attrs, field)

    cond do
      value in allowed ->
        value

      is_binary(value) ->
        case Enum.find(allowed, &(Atom.to_string(&1) == value)) do
          nil ->
            raise invalid(field, "must be one of #{inspect(allowed)}, got: #{inspect(value)}")

          atom ->
            atom
        end

      true ->
        raise invalid(field, "must be one of #{inspect(allowed)}, got: #{inspect(value)}")
    end
  end

  defp non_empty_enum_list(attrs, field, allowed) do
    case value(attrs, field) do
      [_first | _rest] = values ->
        {:ok,
         Enum.map(values, fn value ->
           enum!(%{field => value}, field, allowed)
         end)}

      other ->
        {:error, invalid(field, "must be a non-empty list, got: #{inspect(other)}")}
    end
  end

  defp non_empty_string_list(attrs, field) do
    case value(attrs, field) do
      [_first | _rest] = values ->
        {:ok, Enum.map(values, &string_item!(&1, field))}

      other ->
        {:error, invalid(field, "must be a non-empty list, got: #{inspect(other)}")}
    end
  end

  defp string_list(attrs, field, default) do
    case value(attrs, field) do
      nil -> {:ok, default}
      values when is_list(values) -> {:ok, Enum.map(values, &string_item!(&1, field))}
      other -> {:error, invalid(field, "must be a list, got: #{inspect(other)}")}
    end
  end

  defp string_item!(value, _field) when is_binary(value) and value != "", do: value

  defp string_item!(value, field) do
    raise invalid(field, "must contain only non-empty strings, got: #{inspect(value)}")
  end

  defp optional_put(map, _key, nil), do: map
  defp optional_put(map, key, value), do: Map.put(map, key, value)

  defp normalize(%_{} = value), do: Map.from_struct(value)
  defp normalize(attrs) when is_map(attrs), do: attrs
  defp normalize(attrs) when is_list(attrs), do: Map.new(attrs)

  defp value(attrs, field), do: Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field))

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    Enum.find(
      @package_fields ++
        @entrypoint_fields ++ @intent_fields ++ @envelope_option_fields ++ @forbidden_keys,
      fn
        atom when is_atom(atom) -> Atom.to_string(atom) == key
        _other -> false
      end
    ) || key
  end

  defp normalize_key(key), do: key

  defp stable(%_{} = value), do: value |> Map.from_struct() |> stable()

  defp stable(%{} = value) do
    value
    |> Enum.map(fn {key, nested_value} -> {to_string(key), stable(nested_value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp stable(values) when is_list(values), do: Enum.map(values, &stable/1)
  defp stable(value) when is_atom(value), do: Atom.to_string(value)
  defp stable(value), do: value

  defp invalid(field, message), do: %ArgumentError{message: "#{field} #{message}"}
end
